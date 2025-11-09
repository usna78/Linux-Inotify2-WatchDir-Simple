use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Linux::Inotify2::WatchDir::Simple',
    AUTHOR           => 'OpenTransfer Project',
    VERSION_FROM     => 'lib/Linux/Inotify2/WatchDir/Simple.pm',
    ABSTRACT         => 'Simple polling-based filesystem monitoring with YAML/JSON config',
    LICENSE          => 'perl_5',
    MIN_PERL_VERSION => '5.010',

    PREREQ_PM => {
        # Core inotify interface
        'Linux::Inotify2'   => '2.0',

        # OO framework
        'Moo'               => '2.0',
        'Types::Standard'   => '1.0',

        # Configuration - YAML required
        'YAML::XS'          => '0.80',

        # Logging
        'Log::Log4perl'     => '1.49',

        # Email support
        'Email::Sender'     => '1.300',
        'Email::Simple'     => '2.216',

        # Core Perl modules (should be available)
        'File::Spec'        => 0,
        'File::Find'        => 0,
        'File::Basename'    => 0,
        'Sys::Syslog'       => 0,
        'POSIX'             => 0,
        'Getopt::Long'      => 0,
        'Pod::Usage'        => 0,
        'FindBin'           => 0,
        'Carp'              => 0,
    },

    RECOMMENDS => {
        # For JSON configuration support
        'JSON::PP'          => '4.00',
    },

    TEST_REQUIRES => {
        'Test::More'        => '0.98',
        'Test::Exception'   => '0.43',
        'File::Temp'        => 0,
    },

    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/usna78/Linux-Inotify2-WatchDir-Simple.git',
                web  => 'https://github.com/usna78/Linux-Inotify2-WatchDir-Simple',
            },
            bugtracker => {
                web => 'https://github.com/usna78/Linux-Inotify2-WatchDir-Simple/issues',
            },
        },
        keywords => [
            'inotify',
            'filesystem',
            'monitoring',
            'watch',
            'linux',
            'simple',
            'polling',
            'yaml',
            'json',
            'config',
        ],
    },

    EXE_FILES => ['bin/ywatch'],

    dist  => {
        COMPRESS => 'gzip -9f',
        SUFFIX   => 'gz',
    },

    clean => {
        FILES => 'Linux-Inotify2-WatchDir-Simple-*',
    },
);
