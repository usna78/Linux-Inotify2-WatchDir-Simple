#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use File::Temp qw(tempfile tempdir);
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use_ok('Linux::Inotify2::WatchDir::Simple::Config');

# Create a temporary directory for testing
my $tempdir = tempdir(CLEANUP => 1);

# Test 1: Missing config file
{
    dies_ok {
        Linux::Inotify2::WatchDir::Simple::Config->new(
            config_file => '/nonexistent/file.yml'
        );
    } 'Dies on missing config file';
}

# Test 2: Invalid YAML
{
    my ($fh, $filename) = tempfile(DIR => $tempdir, SUFFIX => '.yml');
    print $fh "invalid: yaml: content:\n  - broken";
    close $fh;

    dies_ok {
        my $config = Linux::Inotify2::WatchDir::Simple::Config->new(
            config_file => $filename
        );
        $config->data;  # Force lazy build
    } 'Dies on invalid YAML';
}

# Test 3: Empty config
{
    my ($fh, $filename) = tempfile(DIR => $tempdir, SUFFIX => '.yml');
    print $fh "---\n";
    close $fh;

    dies_ok {
        my $config = Linux::Inotify2::WatchDir::Simple::Config->new(
            config_file => $filename
        );
        $config->data;  # Force lazy build
    } 'Dies on empty config (no watchlists)';
}

# Test 4: Minimal valid config
{
    my ($fh, $filename) = tempfile(DIR => $tempdir, SUFFIX => '.yml');
    print $fh <<'YAML';
---
watchlists:
  - name: test
    watches:
      - path: TEMPDIR
        events:
          - create
YAML
    close $fh;

    # Replace TEMPDIR placeholder with actual temp directory
    my $content = do {
        open my $in, '<', $filename or die $!;
        local $/;
        <$in>;
    };
    $content =~ s/TEMPDIR/$tempdir/;
    open my $out, '>', $filename or die $!;
    print $out $content;
    close $out;

    my $config;
    lives_ok {
        $config = Linux::Inotify2::WatchDir::Simple::Config->new(
            config_file => $filename
        );
    } 'Minimal valid config loads';

    my $watchlists = $config->watchlists;
    is(scalar @$watchlists, 1, 'One watchlist');
    is($watchlists->[0]{name}, 'test', 'Watchlist name correct');
}

# Test 5: Config with invalid path
{
    my ($fh, $filename) = tempfile(DIR => $tempdir, SUFFIX => '.yml');
    print $fh <<'YAML';
---
watchlists:
  - name: test
    watches:
      - path: /nonexistent/path
        events:
          - create
YAML
    close $fh;

    dies_ok {
        my $config = Linux::Inotify2::WatchDir::Simple::Config->new(
            config_file => $filename
        );
        $config->data;  # Force validation
    } 'Dies on nonexistent watch path';
}

# Test 6: Config with invalid event type
{
    my ($fh, $filename) = tempfile(DIR => $tempdir, SUFFIX => '.yml');
    print $fh <<"YAML";
---
watchlists:
  - name: test
    watches:
      - path: $tempdir
        events:
          - invalid_event
YAML
    close $fh;

    dies_ok {
        my $config = Linux::Inotify2::WatchDir::Simple::Config->new(
            config_file => $filename
        );
        $config->data;  # Force validation
    } 'Dies on invalid event type';
}

# Test 7: Config with invalid regex
{
    my ($fh, $filename) = tempfile(DIR => $tempdir, SUFFIX => '.yml');
    print $fh <<"YAML";
---
watchlists:
  - name: test
    watches:
      - path: $tempdir
        events:
          - create
        filters:
          include: '[invalid regex'
YAML
    close $fh;

    dies_ok {
        my $config = Linux::Inotify2::WatchDir::Simple::Config->new(
            config_file => $filename
        );
        $config->data;  # Force validation
    } 'Dies on invalid regex in filter';
}

# Test 8: Full config with all features
{
    my ($fh, $filename) = tempfile(DIR => $tempdir, SUFFIX => '.yml');
    print $fh <<"YAML";
---
name: TestWatcher
pidfile: $tempdir/test.pid

logging:
  level: INFO
  file: $tempdir/test.log

guard:
  name: Admin
  email: admin\@example.com

email:
  from: test\@example.com
  smtp_host: localhost

watchlists:
  - name: watchlist1
    description: Test watchlist
    enabled: true
    contacts:
      - admin\@example.com
    watches:
      - path: $tempdir
        recursive: true
        events:
          - create
          - modify
        filters:
          include: '\\.txt\$'
          exclude: '~\$'
        actions:
          - type: console
            level: INFO
          - type: syslog
            priority: info
YAML
    close $fh;

    my $config;
    lives_ok {
        $config = Linux::Inotify2::WatchDir::Simple::Config->new(
            config_file => $filename
        );
    } 'Full config loads';

    is($config->data->{name}, 'TestWatcher', 'Config name correct');
    is($config->get_guard_info->{email}, 'admin@example.com', 'Guard email correct');
    is($config->get_email_config->{from}, 'test@example.com', 'Email from correct');

    my $watchlists = $config->watchlists;
    is(scalar @$watchlists, 1, 'One watchlist in full config');
    is($watchlists->[0]{watches}[0]{recursive}, 1, 'Recursive flag set');
}

# Test 9: Disabled watchlist should be filtered out
{
    my ($fh, $filename) = tempfile(DIR => $tempdir, SUFFIX => '.yml');
    print $fh <<"YAML";
---
watchlists:
  - name: enabled
    enabled: true
    watches:
      - path: $tempdir
        events: [create]
  - name: disabled
    enabled: false
    watches:
      - path: $tempdir
        events: [create]
YAML
    close $fh;

    my $config = Linux::Inotify2::WatchDir::Simple::Config->new(
        config_file => $filename
    );

    my $watchlists = $config->watchlists;
    is(scalar @$watchlists, 1, 'Only enabled watchlist returned');
    is($watchlists->[0]{name}, 'enabled', 'Enabled watchlist name correct');
}

done_testing();
