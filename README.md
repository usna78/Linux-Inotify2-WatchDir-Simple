# Linux::Inotify2::WatchDir::Simple

Simple event-driven filesystem monitoring for Linux using inotify.

## Description

**Linux::Inotify2::WatchDir::Simple** is a straightforward filesystem monitoring tool that watches directories for changes and triggers configurable actions. It uses Linux inotify for efficient, event-driven monitoring, making it perfect for configuration file monitoring, batch file processing, and other scenarios requiring reliable change detection.

The name "ywatch" (the included binary) stands for "YAML watch," though both YAML and JSON configuration formats are supported.

## Why "Simple"?

**ywatch is single-purpose**: it only monitors filesystems. Because it doesn't need to juggle multiple types of I/O (network connections, timers, user input, etc.), it can use a straightforward blocking design.

### The Blocking Advantage

When your process only cares about one type of event (filesystem changes), you can simply:
1. Block waiting for the kernel to notify you of filesystem events
2. Process those events immediately when they occur
3. Go back to blocking

This is **more efficient** than event loops because:
- No framework overhead
- No event loop polling multiple sources
- Process sleeps in the kernel (zero CPU) until events arrive
- Events are handled immediately when they occur

### When Event Loops ARE Needed

Event loops (AnyEvent, POE, Mojo) are designed for **complex applications** that monitor multiple I/O sources:
- Web server handling HTTP requests **AND** watching config files
- Database application with network connections **AND** filesystem monitoring
- GUI application responding to user input **AND** file changes

If you only need filesystem monitoring, event loops add unnecessary complexity.

### When to Use ywatch

✅ Perfect for dedicated filesystem monitoring:
- Configuration file monitoring
- Batch file processing directories
- Log file watching
- Any standalone monitoring task

### When NOT to Use ywatch

❌ Not suitable when:
- Your application already uses an event loop for other I/O
- You need to integrate inotify into a larger event-driven system
- You're building a multi-purpose daemon handling various I/O types

**In those cases**, use **Linux::Inotify2** directly and integrate it with your event loop.

## Features

- **YAML and JSON configuration** - Auto-detected from file extension
- **Multiple watchlists** - Monitor different directories with different rules
- **Regex filtering** - Include/exclude files by pattern
- **Multiple action types:**
  - Email notifications (via Email::Sender)
  - Syslog logging
  - Console output (Log::Log4perl)
  - Custom shell commands (sync or async)
- **Signal handling** - SIGHUP reloads config, SIGTERM/SIGINT graceful shutdown
- **Daemon mode** - Run in background with PID file
- **Recursive watching** - Monitor entire directory trees
- **systemd integration** - Template service file included

## Installation

### From CPAN (when published)

```bash
cpan Linux::Inotify2::WatchDir::Simple

From Source

perl Makefile.PL
make
make test
make install

Quick Start
1. Create a configuration file

YAML format (/etc/ywatch/monitor.yml):

---
name: "Config Monitor"
pidfile: "/var/run/ywatch/monitor.pid"

logging:
  level: INFO
  file: "/var/log/ywatch/monitor.log"

watchlists:
  - name: "etc_configs"
    watches:
      - path: "/etc/myapp"
        recursive: true
        events:
          - create
          - modify
          - delete
        filters:
          include: '\\.conf$'
        actions:
          - type: email
            to: "admin@example.com"
            subject: "Config changed: %file%"
          - type: syslog
            priority: warning

JSON format (also supported):

{
  "name": "Config Monitor",
  "watchlists": [
    {
      "name": "etc_configs",
      "watches": [
        {
          "path": "/etc/myapp",
          "recursive": true,
          "events": ["create", "modify"],
          "actions": [
            {
              "type": "syslog",
              "priority": "info"
            }
          ]
        }
      ]
    }
  ]
}

2. Run the monitor

# Validate configuration
ywatch --config /etc/ywatch/monitor.yml --validate

# Run in foreground (for testing)
ywatch --config /etc/ywatch/monitor.yml --debug

# Run as daemon
ywatch --config /etc/ywatch/monitor.yml --daemon

3. Control the monitor

# Reload configuration (SIGHUP)
kill -HUP $(cat /var/run/ywatch/monitor.pid)

# Graceful shutdown (SIGTERM)
kill -TERM $(cat /var/run/ywatch/monitor.pid)

Configuration

See the examples directory for complete configuration examples:

    basic.yml - Simple single-watchlist example
    advanced.yml - Multiple watchlists with all action types
    opentransfer.yml - OpenTransfer-specific configuration

Configuration Elements
Events

Monitor these inotify events:

    create - File/directory created
    modify - File modified
    delete - File/directory deleted
    move - File/directory moved (moved_from + moved_to)
    close_write - File closed after writing
    attrib - Attributes changed
    And many more (see Linux::Inotify2 documentation)

Filters

filters:
  include: '\\.log$'          # Only .log files
  exclude: '~$|\.swp$'        # Exclude temp files

Actions

Email:

- type: email
  to: "admin@example.com"
  subject: "Alert: %file% was %event%"
  body: |
    File: %fullpath%
    Event: %event%
    Time: %timestamp%

Syslog:

- type: syslog
  priority: warning  # emerg, alert, crit, err, warning, notice, info, debug
  facility: local0

Console:

- type: console
  level: WARN  # DEBUG, INFO, WARN, ERROR, FATAL

Command:

- type: command
  execute: "/usr/local/bin/process.sh '%fullpath%'"
  async: true     # Don't block waiting for command
  timeout: 30     # Timeout in seconds

Variable Expansion

Use these variables in action templates:

    %file% - Filename only
    %path% - Directory path
    %fullpath% - Complete file path
    %event% - Event name (CREATE, MODIFY, etc.)
    %timestamp% - Current timestamp

systemd Integration

Install as a systemd service:

# Copy service template
sudo cp systemd/ywatch@.service /etc/systemd/system/

# Create configuration
sudo mkdir -p /etc/ywatch
sudo cp examples/ywatch-basic.yml /etc/ywatch/monitor.yml

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable ywatch@monitor.service
sudo systemctl start ywatch@monitor.service

# View logs
sudo journalctl -u ywatch@monitor.service -f

# Reload configuration
sudo systemctl reload ywatch@monitor.service

The @ syntax allows multiple instances:

systemctl start ywatch@config-monitor.service
systemctl start ywatch@log-monitor.service
systemctl start ywatch@data-monitor.service

Each uses its own config file: /etc/ywatch/<instance-name>.yml
Programmatic Usage

use Linux::Inotify2::WatchDir::Simple;

my $watcher = Linux::Inotify2::WatchDir::Simple->new(
    config_file => '/etc/ywatch/monitor.yml',
    daemon      => 0,
    debug       => 1,
);

# Validate configuration
$watcher->validate();

# Start monitoring (blocks until signal received)
$watcher->run();

Performance Characteristics

| Aspect | Behavior | |--------|----------| | Polling interval | 1 second | | Response time | Up to 1 second delay | | CPU usage | Very low (sleeps between polls) | | Memory usage | Low | | Dependencies | Minimal (no event loops) | | Suitable for | Config monitoring, batch processing | | Not suitable for | High-frequency events, real-time needs |
Comparison: Simple vs. Event (Future)

| Feature | ::Simple | ::Event (future) | |---------|----------|------------------| | Response time | ~1 second | Instant | | Dependencies | Minimal | Event loop required | | Complexity | Low | Moderate | | CPU efficiency | Very good | Excellent | | Best for | Config files, batch | Real-time, high-frequency |
Namespace Design

The Linux::Inotify2::WatchDir::* namespace is designed for multiple implementations:

    ::Simple (this module) - Polling-based, minimal dependencies
    ::Event (future) - Event-loop based for real-time monitoring

Both modules can coexist and serve different use cases.
Requirements

    Perl: 5.10 or higher
    Operating System: Linux with inotify support (kernel 2.6.13+)
    Dependencies: See Makefile.PL for complete list

Core Dependencies

    Linux::Inotify2 (>= 2.0)
    Moo (>= 2.0)
    YAML::XS (>= 0.80)
    Log::Log4perl (>= 1.49)
    Email::Sender (>= 1.300)

Recommended

    JSON (>= 4.00) - For JSON configuration support (automatically uses JSON::XS if available, falls back to JSON::PP)

Security Considerations
Command Execution

The command action executes shell commands. Important:

    Variable expansion does NOT automatically quote or escape
    Malicious filenames could lead to command injection
    Mitigation:
        Quote variables in templates: '/path/script.sh "%fullpath%"'
        Use filters to exclude dangerous patterns
        Validate input in your scripts
        Run ywatch with minimal required privileges

File Access

ywatch requires:

    Read access to monitored directories
    Write access to log files and PID files
    Execute permissions for command actions

Run with the principle of least privilege.
Troubleshooting
"Cannot create inotify watches"

You may have hit the inotify watch limit:

# Check current limit
cat /proc/sys/fs/inotify/max_user_watches

# Increase limit (temporarily)
sudo sysctl fs.inotify.max_user_watches=524288

# Increase limit (permanently)
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

"Configuration validation failed"

Run with --validate and --debug to see detailed error messages:

ywatch --config /path/to/config.yml --validate --debug

Examples

See the examples/ directory for:

    Basic single-directory monitoring
    Advanced multi-watchlist configuration
    Email notification setup
    Command execution examples
    OpenTransfer integration

Development
Running Tests

prove -l t/

Contributing

This module is part of the OpenTransfer project. Contributions welcome!

    Fork the repository
    Create a feature branch
    Make your changes
    Add tests
    Submit a pull request

Author

OpenTransfer Project
License

This is free software; you can redistribute it and/or modify it under the same terms as the Perl 5 programming language system itself.
See Also

    Linux::Inotify2 - The underlying inotify interface
    Log::Log4perl - Logging framework
    Email::Sender - Email delivery
    YAML::XS - YAML parser

Repository

https://github.com/usna78/Linux-Inotify2-WatchDir-Simple
Bug Reports

https://github.com/usna78/Linux-Inotify2-WatchDir-Simple/issues
