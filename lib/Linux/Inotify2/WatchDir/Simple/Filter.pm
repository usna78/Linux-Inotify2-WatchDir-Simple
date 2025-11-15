package Linux::Inotify2::WatchDir::Simple::Filter;

use strict;
use warnings;
use Moo;
use Types::Standard qw(Str Maybe Object);
use File::Basename;

has 'include' => (
    is  => 'ro',
    isa => Maybe [Str],
);

has 'exclude' => (
    is  => 'ro',
    isa => Maybe [Str],
);

has 'include_regex' => (
    is      => 'lazy',
    builder => '_build_include_regex',
);

has 'exclude_regex' => (
    is      => 'lazy',
    builder => '_build_exclude_regex',
);

has 'logger' => (
    is  => 'ro',
    isa => Object,
);

sub _build_include_regex {
    my $self = shift;

    return undef unless $self->include;

    my $pattern = $self->include;
    my $regex;

    eval { $regex = qr/$pattern/; };

    if ($@) {
        my $error = "Invalid include regex pattern: $@";
        $self->logger->error($error) if $self->logger;
        die $error;
    }

    return $regex;
}

sub _build_exclude_regex {
    my $self = shift;

    return undef unless $self->exclude;

    my $pattern = $self->exclude;
    my $regex;

    eval { $regex = qr/$pattern/; };

    if ($@) {
        my $error = "Invalid exclude regex pattern: $@";
        $self->logger->error($error) if $self->logger;
        die $error;
    }

    return $regex;
}

sub matches {
    my ( $self, $filepath ) = @_;

    return 0 unless defined $filepath && $filepath ne '';

    # Get just the filename component
    my $filename = basename($filepath);

    # If include pattern is defined, file must match it
    if ( $self->include_regex ) {
        unless ( $filename =~ $self->include_regex ) {
            $self->logger->debug(
                "File '$filename' does not match include pattern")
              if $self->logger;
            return 0;
        }
    }

    # If exclude pattern is defined, file must NOT match it
    if ( $self->exclude_regex ) {
        if ( $filename =~ $self->exclude_regex ) {
            $self->logger->debug("File '$filename' matches exclude pattern")
              if $self->logger;
            return 0;
        }
    }

    return 1;
}

sub matches_path {
    my ( $self, $filepath ) = @_;

    return 0 unless defined $filepath && $filepath ne '';

    # If include pattern is defined, path must match it
    if ( $self->include_regex ) {
        unless ( $filepath =~ $self->include_regex ) {
            $self->logger->debug(
                "Path '$filepath' does not match include pattern")
              if $self->logger;
            return 0;
        }
    }

    # If exclude pattern is defined, path must NOT match it
    if ( $self->exclude_regex ) {
        if ( $filepath =~ $self->exclude_regex ) {
            $self->logger->debug("Path '$filepath' matches exclude pattern")
              if $self->logger;
            return 0;
        }
    }

    return 1;
}

1;

__END__

=head1 NAME

Linux::Inotify2::WatchDir::Simple::Filter - File filtering for ywatch events

=head1 SYNOPSIS

    use Linux::Inotify2::WatchDir::Simple::Filter;

    my $filter = Linux::Inotify2::WatchDir::Simple::Filter->new(
        include => '\\.conf$',
        exclude => '~$|\\.swp$',
    );

    if ($filter->matches('/etc/myapp/config.conf')) {
        # Process this file
    }

=head1 DESCRIPTION

Provides regex-based filtering for filesystem events.

=head1 ATTRIBUTES

=head1 METHODS

=head2 matches

    my $result = $filter->matches($filename);

Returns true if the filename passes the filter (matches include pattern
and does not match exclude pattern).

=head2 matches_path

    my $result = $filter->matches_path($full_path);

Similar to matches() but uses the full path instead of just the filename.
Useful for more complex filtering scenarios.

=head1 AUTHOR

OpenTransfer Project

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
