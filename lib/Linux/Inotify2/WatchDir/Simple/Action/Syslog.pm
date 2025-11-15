package Linux::Inotify2::WatchDir::Simple::Action::Syslog;

use strict;
use warnings;
use Moo;
use Types::Standard qw(Str);
use Sys::Syslog     qw(:standard :macros);

extends 'Linux::Inotify2::WatchDir::Simple::Action';

has 'priority' => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_priority',
);

has 'facility' => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_facility',
);

has 'message' => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_message',
);

has 'ident' => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_ident',
);

has '_syslog_opened' => (
    is      => 'rw',
    default => 0,
);

sub _build_priority {
    my $self = shift;
    return $self->config->{priority} || 'info';
}

sub _build_facility {
    my $self = shift;
    return $self->config->{facility} || 'user';
}

sub _build_message {
    my $self = shift;
    return $self->config->{message} || 'ywatch: %event% %fullpath%';
}

sub _build_ident {
    my $self = shift;
    return $self->config->{ident} || 'ywatch';
}

sub execute {
    my ( $self, $context ) = @_;

    my $message = $self->expand_variables( $self->message, $context );

    # Open syslog if not already open
    unless ( $self->_syslog_opened ) {
        openlog( $self->ident, 'pid', $self->facility );
        $self->_syslog_opened(1);
    }

    # Map priority string to syslog constant
    my %priority_map = (
        'emerg'   => LOG_EMERG,
        'alert'   => LOG_ALERT,
        'crit'    => LOG_CRIT,
        'err'     => LOG_ERR,
        'error'   => LOG_ERR,
        'warning' => LOG_WARNING,
        'warn'    => LOG_WARNING,
        'notice'  => LOG_NOTICE,
        'info'    => LOG_INFO,
        'debug'   => LOG_DEBUG,
    );

    my $priority_level = $priority_map{ lc( $self->priority ) } || LOG_INFO;

    syslog( $priority_level, '%s', $message );
}

sub DEMOLISH {
    my $self = shift;

    if ( $self->_syslog_opened ) {
        closelog();
    }
}

1;

__END__

=head1 NAME

Linux::Inotify2::WatchDir::Simple::Action::Syslog - Syslog logging action

=head1 SYNOPSIS

    # In YAML config:
    actions:
      - type: syslog
        priority: info
        facility: local0
        message: "File %event%: %fullpath%"

=head1 DESCRIPTION

Logs filesystem events to syslog.

=head1 ATTRIBUTES

=head1 METHODS

=head2 execute

Logs the event to syslog.

=head1 AUTHOR

OpenTransfer Project

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
