package Linux::Inotify2::WatchDir::Simple::Monitor;

use strict;
use warnings;
use Moo;
use Types::Standard qw(Object HashRef ArrayRef);
use Linux::Inotify2;
use File::Spec;
use File::Find;
use File::Basename;
use POSIX qw(strftime);

use Linux::Inotify2::WatchDir::Simple::Filter;
use Linux::Inotify2::WatchDir::Simple::Action;

=head1 NAME

Linux::Inotify2::WatchDir::Simple::Monitor - Core inotify monitoring engine

=head1 SYNOPSIS

    use Linux::Inotify2::WatchDir::Simple::Monitor;

    my $monitor = Linux::Inotify2::WatchDir::Simple::Monitor->new(
        config  => $config_object,
        inotify => $inotify_object,
        logger  => $logger_object,
    );

    $monitor->setup_watches();

=head1 DESCRIPTION

Core monitoring engine that sets up inotify watches and handles events.

=head1 ATTRIBUTES

=cut

has 'config' => (
    is       => 'ro',
    isa      => Object,
    required => 1,
);

has 'inotify' => (
    is       => 'ro',
    isa      => Object,
    required => 1,
);

has 'logger' => (
    is       => 'ro',
    isa      => Object,
    required => 1,
);

has 'watches' => (
    is      => 'rw',
    isa     => ArrayRef,
    default => sub { [] },
);

has 'actions' => (
    is      => 'rw',
    isa     => HashRef,
    default => sub { {} },
);

=head1 METHODS

=cut

=head2 setup_watches

    $monitor->setup_watches();

Sets up inotify watches for all configured watchlists.

=cut

sub setup_watches {
    my $self = shift;

    $self->logger->info("Setting up filesystem watches...");

    my $watchlists = $self->config->watchlists;

    foreach my $watchlist (@$watchlists) {
        $self->_setup_watchlist($watchlist);
    }

    $self->logger->info("All watches established");
}

sub _setup_watchlist {
    my ($self, $watchlist) = @_;

    my $name = $watchlist->{name};
    $self->logger->info("Setting up watchlist: $name");

    my $watches = $watchlist->{watches};

    foreach my $watch_config (@$watches) {
        $self->_setup_watch($watchlist, $watch_config);
    }
}

sub _setup_watch {
    my ($self, $watchlist, $watch_config) = @_;

    my $path = $watch_config->{path};
    my $recursive = $watch_config->{recursive} // 0;

    # Convert event names to inotify masks
    my $mask = $self->_build_event_mask($watch_config->{events});

    # Create filter
    my $filter = Linux::Inotify2::WatchDir::Simple::Filter->new(
        include => $watch_config->{filters}{include} // undef,
        exclude => $watch_config->{filters}{exclude} // undef,
        logger  => $self->logger,
    );

    # Create action handlers
    my $actions = $self->_build_actions($watchlist, $watch_config);

    # Watch directory
    $self->logger->debug("Watching: $path (recursive: $recursive)");

    my $callback = sub {
        my $event = shift;
        $self->_handle_event($event, $filter, $actions, $watchlist, $watch_config);
    };

    # Add watch
    my $watch = $self->inotify->watch($path, $mask, $callback);

    if (!$watch) {
        $self->logger->error("Failed to watch $path: $!");
        return;
    }

    push @{$self->watches}, {
        path      => $path,
        watch     => $watch,
        watchlist => $watchlist->{name},
    };

    # If recursive, watch subdirectories
    if ($recursive) {
        $self->_watch_subdirectories($path, $mask, $callback, $watchlist->{name});
    }
}

sub _watch_subdirectories {
    my ($self, $root_path, $mask, $callback, $watchlist_name) = @_;

    find(
        sub {
            return unless -d $File::Find::name;
            return if $File::Find::name eq $root_path;  # Already watched

            my $watch = $self->inotify->watch($File::Find::name, $mask, $callback);

            if ($watch) {
                $self->logger->debug("Watching subdirectory: $File::Find::name");
                push @{$self->watches}, {
                    path      => $File::Find::name,
                    watch     => $watch,
                    watchlist => $watchlist_name,
                };
            } else {
                $self->logger->warn("Failed to watch subdirectory $File::Find::name: $!");
            }
        },
        $root_path
    );
}

sub _build_event_mask {
    my ($self, $events) = @_;

    # Default events if not specified
    $events ||= ['create', 'modify', 'delete'];

    my %event_map = (
        'create'      => IN_CREATE,
        'modify'      => IN_MODIFY,
        'delete'      => IN_DELETE | IN_DELETE_SELF,
        'move'        => IN_MOVE | IN_MOVE_SELF,
        'move_from'   => IN_MOVED_FROM,
        'move_to'     => IN_MOVED_TO,
        'close_write' => IN_CLOSE_WRITE,
        'attrib'      => IN_ATTRIB,
        'open'        => IN_OPEN,
        'close'       => IN_CLOSE,
        'access'      => IN_ACCESS,
    );

    my $mask = 0;

    foreach my $event (@$events) {
        if (exists $event_map{$event}) {
            $mask |= $event_map{$event};
        } else {
            $self->logger->warn("Unknown event type: $event");
        }
    }

    return $mask;
}

sub _build_actions {
    my ($self, $watchlist, $watch_config) = @_;

    my $action_configs = $watch_config->{actions} || [];
    my @actions;

    foreach my $action_config (@$action_configs) {
        my $action = $self->_create_action($watchlist, $action_config);
        push @actions, $action if $action;
    }

    return \@actions;
}

sub _create_action {
    my ($self, $watchlist, $action_config) = @_;

    my $type = $action_config->{type};

    # Dynamically load action module
    my $class = "Linux::Inotify2::WatchDir::Simple::Action::" . ucfirst($type);

    eval "require $class";
    if ($@) {
        $self->logger->error("Failed to load action class $class: $@");
        return undef;
    }

    # Create action instance
    my $action = eval {
        $class->new(
            config      => $action_config,
            global_config => $self->config,
            logger      => $self->logger,
            watchlist   => $watchlist,
        );
    };

    if ($@) {
        $self->logger->error("Failed to create action $type: $@");
        return undef;
    }

    return $action;
}

sub _handle_event {
    my ($self, $event, $filter, $actions, $watchlist, $watch_config) = @_;

    my $name = $event->name;
    my $fullpath = $event->fullname;

    # Skip if no name (can happen with some events)
    return unless $name;

    # Apply filter
    unless ($filter->matches($fullpath)) {
        $self->logger->debug("Event filtered out: $fullpath");
        return;
    }

    # Determine event type
    my $event_type = $self->_get_event_type($event);

    $self->logger->info("Event: $event_type on $fullpath");

    # Build event context
    my $context = {
        event      => $event_type,
        file       => $name,
        path       => dirname($fullpath),
        fullpath   => $fullpath,
        timestamp  => strftime("%Y-%m-%d %H:%M:%S", localtime),
        watchlist  => $watchlist->{name},
    };

    # Execute actions
    foreach my $action (@$actions) {
        eval {
            $action->execute($context);
        };

        if ($@) {
            $self->logger->error("Action failed: $@");
        }
    }

    # Handle new directories in recursive mode
    if ($watch_config->{recursive} && $event->IN_CREATE && -d $fullpath) {
        $self->logger->debug("New directory created, adding watch: $fullpath");

        my $mask = $self->_build_event_mask($watch_config->{events});
        my $callback = sub {
            my $e = shift;
            $self->_handle_event($e, $filter, $actions, $watchlist, $watch_config);
        };

        my $watch = $self->inotify->watch($fullpath, $mask, $callback);

        if ($watch) {
            push @{$self->watches}, {
                path      => $fullpath,
                watch     => $watch,
                watchlist => $watchlist->{name},
            };
        }
    }
}

sub _get_event_type {
    my ($self, $event) = @_;

    my @types;

    push @types, 'CREATE'      if $event->IN_CREATE;
    push @types, 'MODIFY'      if $event->IN_MODIFY;
    push @types, 'DELETE'      if $event->IN_DELETE;
    push @types, 'DELETE_SELF' if $event->IN_DELETE_SELF;
    push @types, 'MOVED_FROM'  if $event->IN_MOVED_FROM;
    push @types, 'MOVED_TO'    if $event->IN_MOVED_TO;
    push @types, 'MOVE_SELF'   if $event->IN_MOVE_SELF;
    push @types, 'CLOSE_WRITE' if $event->IN_CLOSE_WRITE;
    push @types, 'ATTRIB'      if $event->IN_ATTRIB;
    push @types, 'OPEN'        if $event->IN_OPEN;
    push @types, 'CLOSE'       if $event->IN_CLOSE;
    push @types, 'ACCESS'      if $event->IN_ACCESS;

    return join('|', @types) || 'UNKNOWN';
}

=head2 clear_watches

    $monitor->clear_watches();

Removes all active watches. Used during config reload and shutdown.

=cut

sub clear_watches {
    my $self = shift;

    $self->logger->debug("Clearing all watches");

    foreach my $watch_info (@{$self->watches}) {
        $watch_info->{watch}->cancel() if $watch_info->{watch};
    }

    $self->watches([]);
}

=head1 AUTHOR

OpenTransfer Project

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

1;
