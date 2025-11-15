package Linux::Inotify2::WatchDir::Simple;

use strict;
use warnings;
use Moo;
use Linux::Inotify2;
use Log::Log4perl   qw(:easy);
use Types::Standard qw(Str Bool Object ArrayRef HashRef Maybe);
use File::Spec;
use File::Basename;
use POSIX qw(:signal_h);

use Linux::Inotify2::WatchDir::Simple::Config;
use Linux::Inotify2::WatchDir::Simple::Monitor;
use Linux::Inotify2::WatchDir::Simple::Filter;

our $VERSION = '0.01';

has 'config_file' => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has 'config' => (
    is      => 'lazy',
    isa     => Object,
    builder => '_build_config',
);

has 'monitor' => (
    is      => 'lazy',
    isa     => Object,
    builder => '_build_monitor',
);

has 'inotify' => (
    is      => 'lazy',
    isa     => Object,
    builder => '_build_inotify',
);

has 'running' => (
    is      => 'rw',
    isa     => Bool,
    default => 0,
);

has 'daemon' => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has 'debug' => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has 'logger' => (
    is      => 'lazy',
    isa     => Object,
    builder => '_build_logger',
);

has 'pidfile' => (
    is      => 'lazy',
    isa     => Maybe [Str],
    builder => '_build_pidfile',
);

has '_signal_received' => (
    is      => 'rw',
    isa     => Maybe [Str],
    default => undef,
);

sub _build_config {
    my $self = shift;

    return Linux::Inotify2::WatchDir::Simple::Config->new(
        config_file => $self->config_file,
        logger      => $self->logger,
    );
}

sub _build_monitor {
    my $self = shift;

    return Linux::Inotify2::WatchDir::Simple::Monitor->new(
        config  => $self->config,
        inotify => $self->inotify,
        logger  => $self->logger,
    );
}

sub _build_inotify {
    my $self = shift;

    my $inotify = Linux::Inotify2->new()
      or die "Cannot create Linux::Inotify2 object: $!";

    return $inotify;
}

sub _build_logger {
    my $self = shift;

    my $config = {};

    # If we have a config file that can be parsed, use its settings
    eval {
        my $cfg = Linux::Inotify2::WatchDir::Simple::Config->new(
            config_file => $self->config_file );
        $config = $cfg->data->{logging} || {};
    };

    # Set log level
    my $level = $self->debug ? 'DEBUG' : ( $config->{level} || 'INFO' );

    # Determine appenders based on configuration
    my $appenders   = 'Screen';
    my $file_config = '';

    # Add file appender if specified
    if ( $config->{file} ) {
        my $logfile = $config->{file};
        my $logdir  = dirname($logfile);

        # Create log directory if it doesn't exist
        if ( !-d $logdir ) {
            mkdir( $logdir, 0755 )
              or warn "Cannot create log directory $logdir: $!";
        }

        $appenders .= ', Logfile';
        $file_config = qq{
        log4perl.appender.Logfile = Log::Log4perl::Appender::File
        log4perl.appender.Logfile.filename = $logfile
        log4perl.appender.Logfile.mode = append
        log4perl.appender.Logfile.layout = Log::Log4perl::Layout::PatternLayout
        log4perl.appender.Logfile.layout.ConversionPattern = [%d] [%p] %m%n
        };
    }

    # Configure Log::Log4perl (logger defined only once)
    my $log_config = qq{
        log4perl.logger = $level, $appenders
        log4perl.appender.Screen = Log::Log4perl::Appender::Screen
        log4perl.appender.Screen.stderr = 1
        log4perl.appender.Screen.layout = Log::Log4perl::Layout::PatternLayout
        log4perl.appender.Screen.layout.ConversionPattern = [%d] [%p] %m%n
        $file_config
    };

    Log::Log4perl->init( \$log_config );
    return Log::Log4perl->get_logger();
}

sub _build_pidfile {
    my $self = shift;

    # Try to get from config
    my $pidfile;
    eval {
        my $cfg = Linux::Inotify2::WatchDir::Simple::Config->new(
            config_file => $self->config_file );
        $pidfile = $cfg->data->{pidfile};
    };

    return $pidfile;
}

sub validate {
    my $self = shift;

    $self->logger->info( "Validating configuration: " . $self->config_file );

    # This will die if config is invalid
    my $config = $self->config;

    $self->logger->info("Configuration is valid");
    $self->logger->info( "Name: " . $config->data->{name} )
      if $config->data->{name};

    my $watchlists = $config->data->{watchlists} || [];
    $self->logger->info( "Watchlists: " . scalar(@$watchlists) );

    foreach my $wl (@$watchlists) {
        my $enabled = $wl->{enabled} // 1;
        my $status  = $enabled ? "enabled" : "disabled";
        $self->logger->info("  - $wl->{name} ($status)");
    }

    return 1;
}

sub run {
    my $self = shift;

    $self->logger->info("Starting filesystem monitor...");
    $self->logger->info( "Config: " . $self->config_file );

    # Daemonize if requested
    $self->daemonize() if $self->daemon;

    # Write PID file
    $self->write_pidfile() if $self->pidfile;

    # Setup signal handlers
    $self->setup_signals();

    # Initialize monitoring
    $self->monitor->setup_watches();

    # Execute startup actions
    $self->monitor->execute_startup_actions();

    $self->running(1);
    $self->logger->info("Monitoring started");

    # Main event loop - blocks waiting for filesystem events or signals
    while ( $self->running ) {

        # Check for signals
        if ( my $sig = $self->_signal_received ) {
            $self->logger->info("Received signal: $sig");
            $self->_signal_received(undef);

            if ( $sig eq 'HUP' ) {
                $self->reload();
            }
            elsif ( $sig eq 'TERM' || $sig eq 'INT' ) {
                $self->shutdown();
                last;
            }
        }

        # Poll for inotify events (blocks until events arrive or signal received)
        $self->inotify->poll();
    }

    $self->logger->info("Filesystem monitor stopped");
    $self->cleanup();
}

sub reload {
    my $self = shift;

    $self->logger->info("Reloading configuration...");

    eval {
        # Remove existing watches
        $self->monitor->clear_watches();

        # Reload config
        my $new_config = Linux::Inotify2::WatchDir::Simple::Config->new(
            config_file => $self->config_file,
            logger      => $self->logger,
        );

        # Create new monitor with new config
        my $new_monitor = Linux::Inotify2::WatchDir::Simple::Monitor->new(
            config  => $new_config,
            inotify => $self->inotify,
            logger  => $self->logger,
        );

        # Setup new watches
        $new_monitor->setup_watches();

        # Update objects
        $self->{config}  = $new_config;
        $self->{monitor} = $new_monitor;

        $self->logger->info("Configuration reloaded successfully");
    };

    if ($@) {
        $self->logger->error("Failed to reload configuration: $@");
        $self->logger->error("Continuing with old configuration");
    }
}

sub shutdown {
    my $self = shift;

    $self->logger->info("Shutting down...");
    $self->running(0);
}

sub setup_signals {
    my $self = shift;

    # Use closure to access $self
    $SIG{HUP} = sub {
        $self->_signal_received('HUP');
    };

    $SIG{TERM} = sub {
        $self->_signal_received('TERM');
    };

    $SIG{INT} = sub {
        $self->_signal_received('INT');
    };

    $self->logger->debug("Signal handlers installed");
}

sub daemonize {
    my $self = shift;

    $self->logger->info("Daemonizing...");

    # Fork and exit parent
    my $pid = fork();
    die "Cannot fork: $!" unless defined $pid;
    exit(0) if $pid;    # Parent exits

    # Child continues
    POSIX::setsid() or die "Cannot start new session: $!";

    # Change to root directory
    chdir('/') or die "Cannot chdir to /: $!";

    # Close standard file descriptors
    open( STDIN,  '<', '/dev/null' ) or die "Cannot read /dev/null: $!";
    open( STDOUT, '>', '/dev/null' ) or die "Cannot write /dev/null: $!";
    open( STDERR, '>', '/dev/null' ) or die "Cannot write /dev/null: $!";

    $self->logger->info("Daemonized with PID $$");
}

sub write_pidfile {
    my $self = shift;

    my $pidfile = $self->pidfile or return;

    my $piddir = dirname($pidfile);
    if ( !-d $piddir ) {
        mkdir( $piddir, 0755 ) or die "Cannot create PID directory $piddir: $!";
    }

    open( my $fh, '>', $pidfile ) or die "Cannot write pidfile $pidfile: $!";
    print $fh "$$\n";
    close($fh);

    $self->logger->debug("PID file written: $pidfile");
}

sub cleanup {
    my $self = shift;

    if ( $self->pidfile && -f $self->pidfile ) {
        unlink( $self->pidfile ) or warn "Cannot remove pidfile: $!";
        $self->logger->debug("PID file removed");
    }

    $self->monitor->clear_watches();
}

1;

__END__

=head1 NAME

Linux::Inotify2::WatchDir::Simple - Simple polling-based filesystem monitoring

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

    use Linux::Inotify2::WatchDir::Simple;

    my $watcher = Linux::Inotify2::WatchDir::Simple->new(
        config_file => '/etc/ywatch/monitor.yml',
    );

    $watcher->run();

=head1 DESCRIPTION

Linux::Inotify2::WatchDir::Simple provides a simple, polling-based filesystem
monitoring system built on Linux::Inotify2. It uses a straightforward polling
approach with a 1-second interval, making it suitable for configuration file
monitoring, batch file processing, and other scenarios where sub-second
response time is not critical.

This module allows you to watch multiple directories for various filesystem
events and trigger actions (email, syslog, commands) in response.

Key features:

=over 4

=item * YAML and JSON configuration support

=item * Multiple simultaneous watchlists

=item * Regex-based file filtering

=item * Email notifications via Email::Sender

=item * Syslog integration

=item * Custom command execution

=item * Signal handling (SIGHUP for config reload)

=item * Log::Log4perl integration

=item * Simple polling architecture (no event loop dependencies)

=back

=head1 WHEN TO USE

Use this module when:

=over 4

=item * Monitoring configuration files (changes are infrequent)

=item * Watching directories for batch file arrival

=item * Sub-second response time is not critical

=item * Minimal dependencies are important

=item * Simple, maintainable code is preferred

=back

=head1 WHEN NOT TO USE

Consider alternative approaches for:

=over 4

=item * High-frequency events (hundreds per second)

=item * Real-time processing requirements (sub-second)

=item * Integration with existing event loops

=back

For real-time scenarios, watch for the future C<Linux::Inotify2::WatchDir::Event>
module or use L<Linux::Inotify2> directly with your preferred event loop.

=head1 ATTRIBUTES

=head1 METHODS

=head2 new

    my $watcher = Linux::Inotify2::WatchDir::Simple->new(
        config_file => '/etc/ywatch/monitor.yml',
        daemon      => 1,  # optional
        debug       => 0,  # optional
    );

Creates a new watcher instance.

=head2 validate

    $watcher->validate();

Validates the configuration file without starting the monitor.
Dies on validation errors.

=head2 run

    $watcher->run();

Starts the monitoring loop. This method blocks until a signal is received.

Uses a simple polling approach with 1-second intervals. This is suitable for
most configuration monitoring and batch processing scenarios.

=head2 reload

    $watcher->reload();

Reloads the configuration and re-establishes watches.
Called automatically on SIGHUP.

=head2 shutdown

    $watcher->shutdown();

Initiates graceful shutdown. Called automatically on SIGTERM/SIGINT.

=head2 setup_signals

Sets up signal handlers for SIGHUP, SIGTERM, and SIGINT.

=head2 daemonize

Daemonizes the process (forks to background).

=head2 write_pidfile

Writes the process ID to the pidfile specified in configuration.

=head2 cleanup

Removes pidfile and performs cleanup on shutdown.

=head1 CONFIGURATION

See L<Linux::Inotify2::WatchDir::Simple::Config> for configuration file format.

Both YAML and JSON configuration formats are supported.

=head1 SEE ALSO

L<Linux::Inotify2> - The underlying inotify interface

L<Linux::Inotify2::WatchDir::Simple::Config> - Configuration format

=head1 AUTHOR

OpenTransfer Project

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
