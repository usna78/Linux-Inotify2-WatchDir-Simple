#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use_ok('Linux::Inotify2::WatchDir::Simple::Filter');

# Test 1: No filters (match everything)
{
    my $filter = Linux::Inotify2::WatchDir::Simple::Filter->new();
    ok($filter->matches('/path/to/file.txt'), 'No filter matches any file');
    ok($filter->matches('/path/to/file.log'), 'No filter matches another file');
}

# Test 2: Include filter only
{
    my $filter = Linux::Inotify2::WatchDir::Simple::Filter->new(
        include => '\\.txt$',
    );

    ok($filter->matches('/path/to/file.txt'), 'Include filter matches .txt');
    ok(!$filter->matches('/path/to/file.log'), 'Include filter rejects .log');
    ok($filter->matches('document.txt'), 'Include filter matches filename only');
}

# Test 3: Exclude filter only
{
    my $filter = Linux::Inotify2::WatchDir::Simple::Filter->new(
        exclude => '~$|\\.swp$',
    );

    ok($filter->matches('/path/to/file.txt'), 'Exclude filter allows .txt');
    ok(!$filter->matches('/path/to/file.txt~'), 'Exclude filter rejects backup ~');
    ok(!$filter->matches('/path/to/.file.swp'), 'Exclude filter rejects .swp');
}

# Test 4: Both include and exclude filters
{
    my $filter = Linux::Inotify2::WatchDir::Simple::Filter->new(
        include => '\\.txt$',
        exclude => '^\\.',  # Exclude hidden files
    );

    ok($filter->matches('/path/to/file.txt'), 'Matches visible .txt file');
    ok(!$filter->matches('/path/to/.hidden.txt'), 'Rejects hidden .txt file');
    ok(!$filter->matches('/path/to/file.log'), 'Rejects non-.txt file');
}

# Test 5: Complex patterns
{
    my $filter = Linux::Inotify2::WatchDir::Simple::Filter->new(
        include => '\\.(conf|cfg|ini|yml)$',
        exclude => '\\.bak$|~$|\\.tmp$',
    );

    ok($filter->matches('app.conf'), 'Matches .conf');
    ok($filter->matches('settings.yml'), 'Matches .yml');
    ok($filter->matches('config.ini'), 'Matches .ini');
    ok(!$filter->matches('app.conf.bak'), 'Rejects .bak');
    ok(!$filter->matches('settings.yml~'), 'Rejects ~');
    ok(!$filter->matches('config.tmp'), 'Rejects .tmp');
    ok(!$filter->matches('readme.txt'), 'Rejects non-config file');
}

# Test 6: matches vs matches_path
{
    my $filter = Linux::Inotify2::WatchDir::Simple::Filter->new(
        include => 'config',
    );

    # matches() uses basename
    ok(!$filter->matches('/etc/app/file.txt'), 'matches() uses basename, no match');
    ok($filter->matches('/etc/app/config.txt'), 'matches() basename contains config');

    # matches_path() uses full path
    ok($filter->matches_path('/etc/config/file.txt'), 'matches_path() full path contains config');
    ok(!$filter->matches_path('/etc/app/file.txt'), 'matches_path() full path no match');
}

# Test 7: Case sensitivity
{
    my $filter = Linux::Inotify2::WatchDir::Simple::Filter->new(
        include => '\\.TXT$',  # Uppercase
    );

    ok($filter->matches('file.TXT'), 'Matches uppercase extension');
    ok(!$filter->matches('file.txt'), 'Does not match lowercase (case-sensitive)');
}

# Test 8: Case insensitive
{
    my $filter = Linux::Inotify2::WatchDir::Simple::Filter->new(
        include => '(?i)\\.txt$',  # Case insensitive flag
    );

    ok($filter->matches('file.txt'), 'Case insensitive matches lowercase');
    ok($filter->matches('file.TXT'), 'Case insensitive matches uppercase');
    ok($filter->matches('file.Txt'), 'Case insensitive matches mixed case');
}

# Test 9: Special characters in filenames
{
    my $filter = Linux::Inotify2::WatchDir::Simple::Filter->new(
        include => '\\.log$',
    );

    ok($filter->matches('app-2024.log'), 'Matches filename with dash and digits');
    ok($filter->matches('app_backup.log'), 'Matches filename with underscore');
    ok($filter->matches('app[1].log'), 'Matches filename with brackets');
}

# Test 10: Empty string and edge cases
{
    my $filter = Linux::Inotify2::WatchDir::Simple::Filter->new(
        include => '.',  # Match any character
    );

    ok($filter->matches('a'), 'Matches single character');
    ok(!$filter->matches(''), 'Does not match empty string');
    ok(!$filter->matches(undef), 'Does not match undef');
}

done_testing();
