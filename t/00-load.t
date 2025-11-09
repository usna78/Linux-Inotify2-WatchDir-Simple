#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 10;

# Test that all modules can be loaded

BEGIN {
    use_ok('Linux::Inotify2::WatchDir::Simple')                or BAIL_OUT("Cannot load main module");
    use_ok('Linux::Inotify2::WatchDir::Simple::Config')        or BAIL_OUT("Cannot load Config module");
    use_ok('Linux::Inotify2::WatchDir::Simple::Monitor')       or BAIL_OUT("Cannot load Monitor module");
    use_ok('Linux::Inotify2::WatchDir::Simple::Filter')        or BAIL_OUT("Cannot load Filter module");
    use_ok('Linux::Inotify2::WatchDir::Simple::Action')        or BAIL_OUT("Cannot load Action module");
    use_ok('Linux::Inotify2::WatchDir::Simple::Action::Console') or BAIL_OUT("Cannot load Console action");
    use_ok('Linux::Inotify2::WatchDir::Simple::Action::Syslog')  or BAIL_OUT("Cannot load Syslog action");
    use_ok('Linux::Inotify2::WatchDir::Simple::Action::Email')   or BAIL_OUT("Cannot load Email action");
    use_ok('Linux::Inotify2::WatchDir::Simple::Action::Command') or BAIL_OUT("Cannot load Command action");
}

# Check version
ok(defined $Linux::Inotify2::WatchDir::Simple::VERSION, 'Module has version');

diag("Testing Linux::Inotify2::WatchDir::Simple $Linux::Inotify2::WatchDir::Simple::VERSION");

