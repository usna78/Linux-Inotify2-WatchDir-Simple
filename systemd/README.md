ywatch systemd Integration

This directory contains systemd service templates for running ywatch as a system service.

## Installation

1. Copy the service template to systemd directory:
   ```bash
   sudo cp ywatch@.service /etc/systemd/system/

    Create configuration directory:

    sudo mkdir -p /etc/ywatch

    Copy your configuration file:

    sudo cp your-config.yml /etc/ywatch/monitor.yml

    Reload systemd:

    sudo systemctl daemon-reload

    Enable and start the service:

    sudo systemctl enable ywatch@monitor.service
    sudo systemctl start ywatch@monitor.service

Usage

The @ in the service name is a systemd template parameter. It allows you to run multiple independent ywatch instances with different configurations.
Single Instance

# Start with /etc/ywatch/monitor.yml
sudo systemctl start ywatch@monitor.service

# Check status
sudo systemctl status ywatch@monitor.service

# View logs
sudo journalctl -u ywatch@monitor.service -f

Multiple Instances

# Create multiple config files
sudo cp config1.yml /etc/ywatch/config1.yml
sudo cp config2.yml /etc/ywatch/config2.yml

# Start multiple instances
sudo systemctl start ywatch@config1.service
sudo systemctl start ywatch@config2.service

# Enable auto-start on boot
sudo systemctl enable ywatch@config1.service
sudo systemctl enable ywatch@config2.service

Reload Configuration

To reload the configuration without restarting:

sudo systemctl reload ywatch@monitor.service

This sends SIGHUP to the ywatch process, which reloads the config file.
Troubleshooting
Check Service Status

sudo systemctl status ywatch@monitor.service

View Logs

# Recent logs
sudo journalctl -u ywatch@monitor.service -n 100

# Follow logs in real-time
sudo journalctl -u ywatch@monitor.service -f

# Logs since boot
sudo journalctl -u ywatch@monitor.service -b

Manual Testing

Before enabling the service, test your configuration:

# Validate config
/usr/local/bin/ywatch.pl --config /etc/ywatch/monitor.yml --validate

# Run in foreground with debug
/usr/local/bin/ywatch.pl --config /etc/ywatch/monitor.yml --debug

Customization
User/Group

By default, the service runs as root. To run as a different user:

Edit /etc/systemd/system/ywatch@.service:

[Service]
User=openxfer
Group=openxfer

Make sure the user has:

    Read access to watched directories
    Write access to log files and PID files
    Execute permissions for any command actions

Paths

If ywatch.pl is installed in a different location, update ExecStart:

ExecStart=/usr/bin/ywatch.pl --config /etc/ywatch/%i.yml

Resource Limits

Uncomment and adjust resource limits in the service file:

[Service]
LimitNOFILE=65536
MemoryLimit=512M
CPUQuota=50%

Security Considerations

The default service file includes some security hardening:

    NoNewPrivileges=true - Prevents privilege escalation
    PrivateTmp=true - Uses private /tmp directory

Additional hardening options:

[Service]
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/ywatch /var/run/ywatch
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true

Note: Some options may prevent ywatch from watching certain directories or executing commands.
OpenTransfer Integration

For OpenTransfer-specific service:

# Copy OpenTransfer config
sudo cp config/examples/ywatch-opentransfer.yml /etc/ywatch/opentransfer.yml

# Start service
sudo systemctl enable ywatch@opentransfer.service
sudo systemctl start ywatch@opentransfer.service

Make sure the service user has access to OpenTransfer directories.


---

