package Linux::Inotify2::WatchDir::Simple::Action::Email;

use strict;
use warnings;
use Moo;
use Types::Standard qw(Str ArrayRef);
use Email::Sender::Simple qw(sendmail);
use Email::Simple;
use Email::Simple::Creator;

extends 'Linux::Inotify2::WatchDir::Simple::Action';

=head1 NAME

Linux::Inotify2::WatchDir::Simple::Action::Email - Email notification action

=head1 SYNOPSIS

    # In YAML config:
    actions:
      - type: email
        to: "admin@example.com"
        subject: "File changed: %file%"
        body: |
          Event: %event%
          File: %fullpath%
          Time: %timestamp%

=head1 DESCRIPTION

Sends email notifications for filesystem events using Email::Sender.

=head1 ATTRIBUTES

=cut

has 'to' => (
    is       => 'lazy',
    isa      => ArrayRef[Str],
    builder  => '_build_to',
);

has 'from' => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_from',
);

has 'subject' => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_subject',
);

has 'body' => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_body',
);

sub _build_to {
    my $self = shift;

    my @recipients;

    # Get from action config
    if ($self->config->{to}) {
        my $to = $self->config->{to};
        if (ref $to eq 'ARRAY') {
            push @recipients, @$to;
        } else {
            push @recipients, $to;
        }
    }

    # Add watchlist contacts
    push @recipients, $self->get_contacts();

    # Add guard email as fallback
    unless (@recipients) {
        my $guard = $self->global_config->get_guard_info();
        push @recipients, $guard->{email} if $guard->{email};
    }

    die "No email recipients configured" unless @recipients;

    return \@recipients;
}

sub _build_from {
    my $self = shift;

    # Try action config first
    return $self->config->{from} if $self->config->{from};

    # Try global email config
    my $email_config = $self->global_config->get_email_config();
    return $email_config->{from} if $email_config->{from};

    # Try guard email
    my $guard = $self->global_config->get_guard_info();
    return $guard->{email} if $guard->{email};

    # Fallback
    return 'ywatch@localhost';
}

sub _build_subject {
    my $self = shift;

    return $self->config->{subject} || 'ywatch alert: %event% on %file%';
}

sub _build_body {
    my $self = shift;

    return $self->config->{body} || <<'END_BODY';
A filesystem event has been detected:

Event:     %event%
File:      %file%
Path:      %path%
Full Path: %fullpath%
Time:      %timestamp%
Watchlist: %watchlist%

--
This is an automated message from ywatch.
END_BODY
}

=head1 METHODS

=cut

=head2 execute

Sends email notification about the event.

=cut

sub execute {
    my ($self, $context) = @_;

    my $subject = $self->expand_variables($self->subject, $context);
    my $body = $self->expand_variables($self->body, $context);
    my $from = $self->from;

    foreach my $to (@{$self->to}) {
        eval {
            my $email = Email::Simple->create(
                header => [
                    From    => $from,
                    To      => $to,
                    Subject => $subject,
                ],
                body => $body,
            );

            sendmail($email);

            $self->logger->debug("Email sent to $to");
        };

        if ($@) {
            $self->logger->error("Failed to send email to $to: $@");
        }
    }
}

=head1 TRANSPORT CONFIGURATION

Email::Sender uses Email::Sender::Simple which by default tries sendmail,
then falls back to SMTP. You can configure transport in your environment
or by setting Email::Sender::Transport.

For SMTP configuration, you can use Email::Sender::Transport::SMTP:

    use Email::Sender::Transport::SMTP;
    $ENV{EMAIL_SENDER_TRANSPORT} = 'SMTP';
    $ENV{EMAIL_SENDER_TRANSPORT_host} = 'smtp.example.com';
    $ENV{EMAIL_SENDER_TRANSPORT_port} = 25;

Or configure in your application code before using ywatch.

=head1 AUTHOR

OpenTransfer Project

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

1;
