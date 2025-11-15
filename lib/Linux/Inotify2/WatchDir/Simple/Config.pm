package Linux::Inotify2::WatchDir::Simple::Config;

use strict;
use warnings;
use Moo;
use Types::Standard qw(Str Object HashRef);
use YAML::XS        qw(LoadFile);
use Carp            qw(croak);
use File::Basename  qw(fileparse);

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

sub _build_data {
    my $self = shift;

    my $config_file = $self->config_file;

    # Check file exists
    croak "Configuration file not found: $config_file"
      unless -f $config_file;

    # Check file is readable
    croak "Configuration file not readable: $config_file"
      unless -r $config_file;

    # Detect configuration format from file extension
    my ( $name, $path, $ext ) = fileparse( $config_file, qr/\.[^.]*/ );
    $ext = lc($ext);

    my $data;
    my $format;

    if ( $ext eq '.json' ) {
        # JSON configuration
        $format = 'JSON';

        # Try to load JSON (tries JSON::XS first, falls back to JSON::PP)
        eval { require JSON; };
        if ($@) {
            croak
"JSON configuration requires JSON module (install with: cpanm JSON)";
        }

        # Parse JSON
        eval {
            open my $fh, '<', $config_file
              or die "Cannot open file: $!";
            local $/;
            my $json_text = <$fh>;
            close $fh;
            $data = JSON->new->utf8->decode($json_text);

            # Convert JSON boolean objects to plain Perl booleans
            $data = $self->_convert_json_booleans($data);
        };

        if ($@) {
            croak "Failed to parse JSON configuration: $@";
        }
    }
    elsif ( $ext eq '.yml' || $ext eq '.yaml' ) {
        # YAML configuration
        $format = 'YAML';
        eval { $data = LoadFile($config_file); };

        if ($@) {
            croak "Failed to parse YAML configuration: $@";
        }
    }
    else {
        croak
"Unknown configuration file format: $ext (supported: .yml, .yaml, .json)";
    }

    croak "Configuration file is empty or invalid"
      unless $data && ref($data) eq 'HASH';

    # Validate configuration structure
    $self->validate($data);

    return $data;
}

sub _convert_json_booleans {
    my ( $self, $data ) = @_;

    # Recursively convert JSON boolean objects to plain Perl booleans
    # Works with any JSON backend (JSON::XS, JSON::PP, Cpanel::JSON::XS, etc.)
    if ( ref($data) eq 'HASH' ) {
        foreach my $key ( keys %$data ) {
            $data->{$key} = $self->_convert_json_booleans( $data->{$key} );
        }
    }
    elsif ( ref($data) eq 'ARRAY' ) {
        for ( my $i = 0 ; $i < @$data ; $i++ ) {
            $data->[$i] = $self->_convert_json_booleans( $data->[$i] );
        }
    }
    elsif ( JSON::is_bool($data) ) {
        # Convert JSON boolean to plain Perl boolean
        # Works for JSON::XS::Boolean, JSON::PP::Boolean, Cpanel::JSON::XS::Boolean
        return $data ? 1 : 0;
    }

    return $data;
}

sub validate {
    my ( $self, $data ) = @_;

    # Watchlists are required
    croak "Configuration must contain 'watchlists' section"
      unless exists $data->{watchlists};

    croak "'watchlists' must be an array"
      unless ref( $data->{watchlists} ) eq 'ARRAY';

    croak "At least one watchlist is required"
      unless @{ $data->{watchlists} } > 0;

    # Validate each watchlist
    foreach my $wl ( @{ $data->{watchlists} } ) {
        $self->_validate_watchlist($wl);
    }

    # Validate email config if present
    if ( $data->{email} ) {
        croak "'email' section must be a hash"
          unless ref( $data->{email} ) eq 'HASH';
    }

    # Validate logging config if present
    if ( $data->{logging} ) {
        croak "'logging' section must be a hash"
          unless ref( $data->{logging} ) eq 'HASH';

        if ( $data->{logging}{level} ) {
            my $level = uc( $data->{logging}{level} );
            croak
"Invalid log level: $level (must be DEBUG, INFO, WARN, ERROR, or FATAL)"
              unless $level =~ /^(DEBUG|INFO|WARN|ERROR|FATAL)$/;
        }
    }

    # Validate startup_actions if present
    if ( $data->{startup_actions} ) {
        croak "'startup_actions' must be an array"
          unless ref( $data->{startup_actions} ) eq 'ARRAY';

        foreach my $action ( @{ $data->{startup_actions} } ) {
            $self->_validate_action($action);
        }
    }

    return 1;
}

sub _validate_watchlist {
    my ( $self, $wl ) = @_;

    croak "Watchlist must be a hash"
      unless ref($wl) eq 'HASH';

    croak "Watchlist must have 'name' field"
      unless $wl->{name};

    croak "Watchlist must have 'watches' array"
      unless $wl->{watches} && ref( $wl->{watches} ) eq 'ARRAY';

    croak "Watchlist must have at least one watch"
      unless @{ $wl->{watches} } > 0;

    # Validate each watch
    foreach my $watch ( @{ $wl->{watches} } ) {
        $self->_validate_watch($watch);
    }
}

sub _validate_watch {
    my ( $self, $watch ) = @_;

    croak "Watch must be a hash"
      unless ref($watch) eq 'HASH';

    croak "Watch must have 'path' field"
      unless $watch->{path};

    croak "Watch path does not exist: $watch->{path}"
      unless -e $watch->{path};

    croak "Watch path is not a directory: $watch->{path}"
      unless -d $watch->{path};

    # Events are optional, but if present must be valid
    if ( $watch->{events} ) {
        croak "Watch 'events' must be an array"
          unless ref( $watch->{events} ) eq 'ARRAY';

        my %valid_events = map { $_ => 1 } qw(
          create modify delete move close_write
          attrib open close access move_from move_to
        );

        foreach my $event ( @{ $watch->{events} } ) {
            croak "Invalid event type: $event"
              unless $valid_events{$event};
        }
    }

    # Filters are optional
    if ( $watch->{filters} ) {
        croak "Watch 'filters' must be a hash"
          unless ref( $watch->{filters} ) eq 'HASH';

        # Validate regex patterns
        if ( $watch->{filters}{include} ) {
            eval { qr/$watch->{filters}{include}/ };
            croak "Invalid regex in filters.include: $@" if $@;
        }

        if ( $watch->{filters}{exclude} ) {
            eval { qr/$watch->{filters}{exclude}/ };
            croak "Invalid regex in filters.exclude: $@" if $@;
        }
    }

    # Actions are optional
    if ( $watch->{actions} ) {
        croak "Watch 'actions' must be an array"
          unless ref( $watch->{actions} ) eq 'ARRAY';

        foreach my $action ( @{ $watch->{actions} } ) {
            $self->_validate_action($action);
        }
    }
}

sub _validate_action {
    my ( $self, $action ) = @_;

    croak "Action must be a hash"
      unless ref($action) eq 'HASH';

    croak "Action must have 'type' field"
      unless $action->{type};

    my %valid_types = map { $_ => 1 } qw(email syslog console command);

    croak "Invalid action type: $action->{type}"
      unless $valid_types{ $action->{type} };

    # Type-specific validation
    if ( $action->{type} eq 'email' ) {
        croak "Email action must have 'to' field"
          unless $action->{to};
    }

    if ( $action->{type} eq 'command' ) {
        croak "Command action must have 'execute' field"
          unless $action->{execute};
    }
}

sub watchlists {
    my $self = shift;

    my @enabled = grep { $_->{enabled} // 1 } @{ $self->data->{watchlists} };
    return \@enabled;
}

sub get_email_config {
    my $self = shift;

    return $self->data->{email} || {};
}

sub get_logging_config {
    my $self = shift;

    return $self->data->{logging} || {};
}

sub get_guard_info {
    my $self = shift;

    return $self->data->{guard} || {};
}

sub get_startup_actions {
    my $self = shift;

    return $self->data->{startup_actions} || [];
}

1;

__END__

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

=head1 METHODS

=head2 validate

    $config->validate($data);

Validates the configuration data structure. Dies on validation errors.

=head2 watchlists

    my $watchlists = $config->watchlists;

Returns array reference of enabled watchlists.

=head2 get_email_config

    my $email_config = $config->get_email_config;

Returns email configuration hash.

=head2 get_logging_config

    my $log_config = $config->get_logging_config;

Returns logging configuration hash.

=head2 get_guard_info

    my $guard = $config->get_guard_info;

Returns guard/contact information.

=head2 get_startup_actions

    my $actions = $config->get_startup_actions;

Returns array reference of startup actions.

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
