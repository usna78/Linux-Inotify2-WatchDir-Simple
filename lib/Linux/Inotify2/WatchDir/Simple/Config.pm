package Linux::Inotify2::WatchDir::Simple::Config;

use strict;
use warnings;
use Moo;
use Types::Standard qw(Str Object HashRef);
use YAML::XS qw(LoadFile);
use Carp qw(croak);

=head1 NAME

Linux::Inotify2::WatchDir::Simple::Config - Configuration parser for ywatch

=head1 SYNOPSIS

    use Linux::Inotify2::WatchDir::Simple::Config;

    my $config = Linux::Inotify2::WatchDir::Simple::Config->new(
        config_file => '/etc/ywatch/monitor.yml',
    );

    my $data = $config->data;
    my $watchlists = $config->watchlists;

=head1 DESCRIPTION

Parses and validates YAML configuration files for ywatch.

=head1 ATTRIBUTES

=cut

has 'config_file' => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has 'logger' => (
    is  => 'ro',
    isa => Object,
);

has 'data' => (
    is      => 'ro',
    isa     => HashRef,
    builder => '_build_data',
);

=head1 METHODS

=cut

sub _build_data {
    my $self = shift;

    my $config_file = $self->config_file;

    # Check file exists
    croak "Configuration file not found: $config_file"
        unless -f $config_file;

    # Check file is readable
    croak "Configuration file not readable: $config_file"
        unless -r $config_file;

    # Load YAML
    my $data;
    eval {
        $data = LoadFile($config_file);
    };

    if ($@) {
        croak "Failed to parse YAML configuration: $@";
    }

    croak "Configuration file is empty or invalid"
        unless $data && ref($data) eq 'HASH';

    # Validate configuration structure
    $self->validate($data);

    return $data;
}

=head2 validate

    $config->validate($data);

Validates the configuration data structure. Dies on validation errors.

=cut

sub validate {
    my ($self, $data) = @_;

    # Watchlists are required
    croak "Configuration must contain 'watchlists' section"
        unless exists $data->{watchlists};

    croak "'watchlists' must be an array"
        unless ref($data->{watchlists}) eq 'ARRAY';

    croak "At least one watchlist is required"
        unless @{$data->{watchlists}} > 0;

    # Validate each watchlist
    foreach my $wl (@{$data->{watchlists}}) {
        $self->_validate_watchlist($wl);
    }

    # Validate email config if present
    if ($data->{email}) {
        croak "'email' section must be a hash"
            unless ref($data->{email}) eq 'HASH';
    }

    # Validate logging config if present
    if ($data->{logging}) {
        croak "'logging' section must be a hash"
            unless ref($data->{logging}) eq 'HASH';

        if ($data->{logging}{level}) {
            my $level = uc($data->{logging}{level});
            croak "Invalid log level: $level (must be DEBUG, INFO, WARN, ERROR, or FATAL)"
                unless $level =~ /^(DEBUG|INFO|WARN|ERROR|FATAL)$/;
        }
    }

    return 1;
}

sub _validate_watchlist {
    my ($self, $wl) = @_;

    croak "Watchlist must be a hash"
        unless ref($wl) eq 'HASH';

    croak "Watchlist must have 'name' field"
        unless $wl->{name};

    croak "Watchlist must have 'watches' array"
        unless $wl->{watches} && ref($wl->{watches}) eq 'ARRAY';

    croak "Watchlist must have at least one watch"
        unless @{$wl->{watches}} > 0;

    # Validate each watch
    foreach my $watch (@{$wl->{watches}}) {
        $self->_validate_watch($watch);
    }
}

sub _validate_watch {
    my ($self, $watch) = @_;

    croak "Watch must be a hash"
        unless ref($watch) eq 'HASH';

    croak "Watch must have 'path' field"
        unless $watch->{path};

    croak "Watch path does not exist: $watch->{path}"
        unless -e $watch->{path};

    croak "Watch path is not a directory: $watch->{path}"
        unless -d $watch->{path};

    # Events are optional, but if present must be valid
    if ($watch->{events}) {
        croak "Watch 'events' must be an array"
            unless ref($watch->{events}) eq 'ARRAY';

        my %valid_events = map { $_ => 1 } qw(
            create modify delete move close_write
            attrib open close access move_from move_to
        );

        foreach my $event (@{$watch->{events}}) {
            croak "Invalid event type: $event"
                unless $valid_events{$event};
        }
    }

    # Filters are optional
    if ($watch->{filters}) {
        croak "Watch 'filters' must be a hash"
            unless ref($watch->{filters}) eq 'HASH';

        # Validate regex patterns
        if ($watch->{filters}{include}) {
            eval { qr/$watch->{filters}{include}/ };
            croak "Invalid regex in filters.include: $@" if $@;
        }

        if ($watch->{filters}{exclude}) {
            eval { qr/$watch->{filters}{exclude}/ };
            croak "Invalid regex in filters.exclude: $@" if $@;
        }
    }

    # Actions are optional
    if ($watch->{actions}) {
        croak "Watch 'actions' must be an array"
            unless ref($watch->{actions}) eq 'ARRAY';

        foreach my $action (@{$watch->{actions}}) {
            $self->_validate_action($action);
        }
    }
}

sub _validate_action {
    my ($self, $action) = @_;

    croak "Action must be a hash"
        unless ref($action) eq 'HASH';

    croak "Action must have 'type' field"
        unless $action->{type};

    my %valid_types = map { $_ => 1 } qw(email syslog console command);

    croak "Invalid action type: $action->{type}"
        unless $valid_types{$action->{type}};

    # Type-specific validation
    if ($action->{type} eq 'email') {
        croak "Email action must have 'to' field"
            unless $action->{to};
    }

    if ($action->{type} eq 'command') {
        croak "Command action must have 'execute' field"
            unless $action->{execute};
    }
}

=head2 watchlists

    my $watchlists = $config->watchlists;

Returns array reference of enabled watchlists.

=cut

sub watchlists {
    my $self = shift;

    my @enabled = grep { $_->{enabled} // 1 } @{$self->data->{watchlists}};
    return \@enabled;
}

=head2 get_email_config

    my $email_config = $config->get_email_config;

Returns email configuration hash.

=cut

sub get_email_config {
    my $self = shift;

    return $self->data->{email} || {};
}

=head2 get_logging_config

    my $log_config = $config->get_logging_config;

Returns logging configuration hash.

=cut

sub get_logging_config {
    my $self = shift;

    return $self->data->{logging} || {};
}

=head2 get_guard_info

    my $guard = $config->get_guard_info;

Returns guard/contact information.

=cut

sub get_guard_info {
    my $self = shift;

    return $self->data->{guard} || {};
}

=head1 CONFIGURATION FORMAT

Example YAML configuration:

    ---
    name: "MyWatcher"
    pidfile: "/var/run/ywatch/watcher.pid"

    logging:
      level: INFO
      file: "/var/log/ywatch/watcher.log"
      console: true

    guard:
      name: "System Administrator"
      email: "admin@example.com"

    email:
      from: "ywatch@example.com"
      smtp_host: "localhost"
      smtp_port: 25

    watchlists:
      - name: "config_monitor"
        description: "Monitor configuration files"
        enabled: true

        watches:
          - path: "/etc/myapp"
            recursive: true
            events:
              - create
              - modify
              - delete
            filters:
              include: '\\.conf$'
              exclude: '~$|\\.swp$'
            actions:
              - type: email
                to: "admin@example.com"
                subject: "Config changed: %file%"
              - type: syslog
                priority: info
              - type: command
                execute: "/usr/local/bin/validate.sh %fullpath%"

=head1 AUTHOR

OpenTransfer Project

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

1;
