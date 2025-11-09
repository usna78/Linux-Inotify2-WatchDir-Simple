package Linux::Inotify2::WatchDir::Simple::Action::Command;

use strict;
use warnings;
use Moo;
use Types::Standard qw(Str Bool Int);
use POSIX ":sys_wait_h";

extends 'Linux::Inotify2::WatchDir::Simple::Action';

=head1 NAME

Linux::Inotify2::WatchDir::Simple::Action::Command - Execute shell commands

=head1 SYNOPSIS

    # In YAML config:
    actions:
      - type: command
        execute: "/usr/local/bin/process.sh %fullpath%"
        async: true
        timeout: 30

=head1 DESCRIPTION

Executes shell commands in response to filesystem events.

=head1 ATTRIBUTES

=cut

has 'execute' => (
    is       => 'lazy',
    isa      => Str,
    builder  => '_build_execute',
);

has 'async' => (
    is      => 'lazy',
    isa     => Bool,
    builder => '_build_async',
);

has 'timeout' => (
    is      => 'lazy',
    isa     => Int,
    builder => '_build_timeout',
);

has 'shell' => (
    is      => 'lazy',
    isa     => Str,
    builder => '_build_shell',
);

sub _build_execute {
    my $self = shift;

    die "Command action requires 'execute' parameter"
        unless $self->config->{execute};

    return $self->config->{execute};
}

sub _build_async {
    my $self = shift;
    return $self->config->{async} // 1;  # Default to async
}

sub _build_timeout {
    my $self = shift;
    return $self->config->{timeout} || 30;
}

sub _build_shell {
    my $self = shift;
    return $self->config->{shell} || '/bin/bash';
}

=head1 METHODS

=cut

=head2 execute

Executes the command.

=cut

sub execute {
    my ($self, $context) = @_;

    my $command = $self->expand_variables($self->execute, $context);

    $self->logger->debug("Executing command: $command");

    if ($self->async) {
        $self->_execute_async($command);
    } else {
        $self->_execute_sync($command);
    }
}

sub _execute_sync {
    my ($self, $command) = @_;

    my $output;
    my $exit_code;

    eval {
        # Set up alarm for timeout
        local $SIG{ALRM} = sub { die "Command timeout\n" };
        alarm($self->timeout);

        # Execute command
        $output = `$command 2>&1`;
        $exit_code = $? >> 8;

        alarm(0);  # Cancel alarm
    };

    if ($@) {
        if ($@ eq "Command timeout\n") {
            $self->logger->error("Command timed out after " . $self->timeout . " seconds: $command");
        } else {
            $self->logger->error("Command execution failed: $@");
        }
        return;
    }

    if ($exit_code != 0) {
        $self->logger->warn("Command exited with code $exit_code: $command");
        $self->logger->debug("Output: $output") if $output;
    } else {
        $self->logger->debug("Command completed successfully");
        $self->logger->debug("Output: $output") if $output;
    }
}

sub _execute_async {
    my ($self, $command) = @_;

    my $pid = fork();

    if (!defined $pid) {
        $self->logger->error("Fork failed: $!");
        return;
    }

    if ($pid == 0) {
        # Child process
        eval {
            # Set up alarm for timeout
            local $SIG{ALRM} = sub { exit(124) };  # 124 = timeout exit code
            alarm($self->timeout);

            # Execute command
            exec($command);

            # If exec fails
            exit(126);
        };

        # Should not reach here
        exit(127);
    }

    # Parent process
    $self->logger->debug("Command started with PID $pid");

    # Non-blocking wait to reap zombie processes
    $SIG{CHLD} = sub {
        while ((my $child = waitpid(-1, WNOHANG)) > 0) {
            my $exit_code = $? >> 8;
            if ($exit_code == 124) {
                $self->logger->warn("Child process $child timed out");
            } elsif ($exit_code != 0) {
                $self->logger->warn("Child process $child exited with code $exit_code");
            }
        }
    };
}

=head1 SECURITY CONSIDERATIONS

Commands are executed through the system shell, which means they are subject
to shell injection if the command template includes unsanitized input.

The variable expansion (%file%, %path%, etc.) does NOT perform any escaping
or quoting. If your filesystem may contain files with special characters,
you should:

1. Validate/sanitize filenames in your command script
2. Use proper quoting in your command template
3. Consider using filters to exclude problematic filenames

Example safe command templates:

    # Quote the fullpath variable
    execute: '/usr/local/bin/process.sh "%fullpath%"'

    # Or pass through stdin to avoid shell expansion
    execute: 'echo "%fullpath%" | /usr/local/bin/process.sh'

=head1 AUTHOR

OpenTransfer Project

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

1;
