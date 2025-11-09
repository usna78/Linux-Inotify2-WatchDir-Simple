package Linux::Inotify2::WatchDir::Simple::Action::Console;

use strict;
use warnings;
use Moo;
use Types::Standard qw(Str);

extends 'Linux::Inotify2::WatchDir::Simple::Action';

=head1 NAME

Linux::Inotify2::WatchDir::Simple::Action::Console - Console logging action

=head1 SYNOPSIS

    # In YAML config:
    actions:
      - type: console
        level: INFO
        format: "File %event%: %fullpath%"

=head1 DESCRIPTION

Logs filesystem events to console using Log::Log4perl.

=head1 ATTRIBUTES

=cut

has 'level' => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_level',
);

has 'format' => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_format',
);

sub _build_level {
    my $self = shift;
    return uc($self->config->{level} || 'INFO');
}

sub _build_format {
    my $self = shift;
    return $self->config->{format} || 'File %event%: %fullpath%';
}

=head1 METHODS

=cut

=head2 execute

Logs the event to console.

=cut

sub execute {
    my ($self, $context) = @_;

    my $message = $self->expand_variables($self->format, $context);
    my $level = lc($self->level);

    # Map to Log::Log4perl methods
    if ($level eq 'debug') {
        $self->logger->debug($message);
    } elsif ($level eq 'info') {
        $self->logger->info($message);
    } elsif ($level eq 'warn' || $level eq 'warning') {
        $self->logger->warn($message);
    } elsif ($level eq 'error') {
        $self->logger->error($message);
    } elsif ($level eq 'fatal') {
        $self->logger->fatal($message);
    } else {
        $self->logger->info($message);
    }
}

=head1 AUTHOR

OpenTransfer Project

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

1;
