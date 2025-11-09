package Linux::Inotify2::WatchDir::Simple::Action;

use strict;
use warnings;
use Moo;
use Types::Standard qw(Object HashRef);

=head1 NAME

Linux::Inotify2::WatchDir::Simple::Action - Base class for ywatch actions

=head1 SYNOPSIS

    package Linux::Inotify2::WatchDir::Simple::Action::MyAction;
    use Moo;
    extends 'Linux::Inotify2::WatchDir::Simple::Action';

    sub execute {
        my ($self, $context) = @_;
        # Implement action logic
    }

=head1 DESCRIPTION

Base class for all action handlers. Provides common functionality for
processing filesystem events.

=head1 ATTRIBUTES

=cut

has 'config' => (
    is       => 'ro',
    isa      => HashRef,
    required => 1,
);

has 'global_config' => (
    is       => 'ro',
    isa      => Object,
    required => 1,
);

has 'logger' => (
    is       => 'ro',
    isa      => Object,
    required => 1,
);

has 'watchlist' => (
    is       => 'ro',
    isa      => HashRef,
    required => 1,
);

=head1 METHODS

=cut

=head2 execute

    $action->execute($context);

Executes the action. Must be overridden by subclasses.

Context hash contains:
    event      => Event type (CREATE, MODIFY, etc.)
    file       => Filename
    path       => Directory path
    fullpath   => Full file path
    timestamp  => Event timestamp
    watchlist  => Watchlist name

=cut

sub execute {
    my ($self, $context) = @_;

    die "execute() must be implemented by subclass";
}

=head2 expand_variables

    my $expanded = $action->expand_variables($template, $context);

Expands template variables using context data.

Variables:
    %file%      => Filename
    %path%      => Directory path
    %fullpath%  => Full path
    %event%     => Event type
    %timestamp% => Timestamp
    %watchlist% => Watchlist name

=cut

sub expand_variables {
    my ($self, $template, $context) = @_;

    return '' unless defined $template;

    my $expanded = $template;

    # Replace variables
    $expanded =~ s/%file%/$context->{file}/g;
    $expanded =~ s/%path%/$context->{path}/g;
    $expanded =~ s/%fullpath%/$context->{fullpath}/g;
    $expanded =~ s/%event%/$context->{event}/g;
    $expanded =~ s/%timestamp%/$context->{timestamp}/g;
    $expanded =~ s/%watchlist%/$context->{watchlist}/g;

    return $expanded;
}

=head2 get_contacts

    my @contacts = $action->get_contacts();

Returns list of contact email addresses from watchlist configuration.

=cut

sub get_contacts {
    my $self = shift;

    my $contacts = $self->watchlist->{contacts} || [];
    my @emails;

    foreach my $contact (@$contacts) {
        if (ref $contact eq 'HASH') {
            push @emails, $contact->{email} if $contact->{email};
        } else {
            push @emails, $contact;
        }
    }

    return @emails;
}

=head1 AUTHOR

OpenTransfer Project

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

1;

