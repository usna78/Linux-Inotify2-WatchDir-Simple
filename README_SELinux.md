# SELinux Configuration for ywatch

This guide covers SELinux configuration requirements for running ywatch under systemd on RHEL-based distributions (Red Hat Enterprise Linux, Rocky Linux, CentOS, Fedora, AlmaLinux).

## Quick Start

If you're experiencing issues on a fresh SELinux system, run these commands:

```bash
# 1. Fix file permissions
sudo chmod 755 /usr/local/bin/ywatch

# 2. Set SELinux context
sudo semanage fcontext -a -t bin_t "/usr/local/bin/ywatch"
sudo restorecon -v /usr/local/bin/ywatch

# 3. Configure SMTP email delivery (edit your config)
sudo nano /etc/ywatch/monitor.yml
```

Add to your ywatch config:
```yaml
email:
  from: "ywatch@localhost"
  smtp_host: "localhost"
  smtp_port: 25
```

Update systemd service:
```bash
sudo nano /etc/systemd/system/ywatch@.service
```

Add under `[Service]`:
```ini
Environment="EMAIL_SENDER_TRANSPORT=SMTP"
Environment="EMAIL_SENDER_TRANSPORT_host=localhost"
Environment="EMAIL_SENDER_TRANSPORT_port=25"
```

Reload and restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart ywatch@monitor.service
```

## Common SELinux Issues

### Issue 1: Executable Permission Denied

**Symptoms:**
```
ywatch@monitor.service: Failed at step EXEC spawning /usr/local/bin/ywatch: Permission denied
```

Service fails immediately and systemd keeps trying to restart it.

**Root Causes:**

1. **Incorrect file permissions** - The ywatch executable may have restrictive permissions (e.g., `750` instead of `755`)
2. **Missing SELinux context** - The file doesn't have the proper SELinux type label for executables

**Solutions:**

#### Step 1: Fix File Permissions

```bash
# Check current permissions
ls -l /usr/local/bin/ywatch

# Should show: -rwxr-xr-x (755)
# If it shows: -rwxr-x--- (750), fix it:
sudo chmod 755 /usr/local/bin/ywatch
```

The issue: systemd runs as root, but with permissions like `750` (owner=rwx, group=rx, others=none), root running the systemd service cannot execute the file because it falls into the "others" category when the file is owned by a different user.

#### Step 2: Set SELinux Context

```bash
# Check current SELinux context
ls -Z /usr/local/bin/ywatch

# Set proper context for executable binaries
sudo semanage fcontext -a -t bin_t "/usr/local/bin/ywatch"
sudo restorecon -v /usr/local/bin/ywatch

# Verify the change
ls -Z /usr/local/bin/ywatch
# Should show: unconfined_u:object_r:bin_t:s0
```

If `semanage` is not found, install it:
```bash
sudo dnf install policycoreutils-python-utils
```

#### Step 3: Test

```bash
sudo systemctl start ywatch@monitor.service
sudo systemctl status ywatch@monitor.service
```

### Issue 2: Email Delivery Failures

**Symptoms:**

- Emails configured in ywatch actions are not being delivered
- SELinux audit logs show denials related to postfix/sendmail
- Deferred messages accumulate in postfix queue

**Root Cause:**

By default, `Email::Sender::Simple` (used by ywatch) invokes the `sendmail` command, which attempts to write to `/var/spool/postfix/maildrop`. When ywatch runs under systemd with SELinux enforcing, the service's security context prevents this operation.

**Check for SELinux Denials:**

```bash
# View recent SELinux denials
sudo ausearch -m avc -ts recent | grep -E 'postfix|sendmail|ywatch'

# Check postfix mail queue
mailq

# View postfix logs
sudo tail -f /var/log/maillog
```

**Solutions:**

There are three approaches to fix email delivery. We recommend **Solution 1** (SMTP) as it's the cleanest and most portable.

#### Solution 1: Use SMTP Transport (Recommended)

This bypasses the sendmail/maildrop interaction entirely by connecting directly to the local postfix SMTP port.

**How it works:**
```
ywatch → postfix (localhost:25) → remote email server
```

This does NOT limit you to local delivery. Your local postfix will relay to remote email addresses.

**Configuration Steps:**

1. Edit your ywatch configuration file:

```bash
sudo nano /etc/ywatch/monitor.yml
```

Add or update the email section:
```yaml
email:
  from: "ywatch@localhost"
  smtp_host: "localhost"
  smtp_port: 25
```

2. Configure systemd to use SMTP transport:

```bash
sudo nano /etc/systemd/system/ywatch@.service
```

Add these lines in the `[Service]` section:
```ini
[Service]
# ... existing settings ...

# Configure Email::Sender to use SMTP instead of sendmail
Environment="EMAIL_SENDER_TRANSPORT=SMTP"
Environment="EMAIL_SENDER_TRANSPORT_host=localhost"
Environment="EMAIL_SENDER_TRANSPORT_port=25"
```

3. Reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ywatch@monitor.service
```

4. Test email delivery:

```bash
# Trigger an event that sends email, or test postfix directly:
echo "Test message" | mail -s "Test from $(hostname)" your-email@example.com

# Watch the logs
sudo journalctl -u ywatch@monitor.service -f
sudo tail -f /var/log/maillog
```

**Advantages:**
- No SELinux policy changes needed
- More portable across systems
- Easier to configure for remote SMTP servers later
- Better error logging
- Recommended approach for production

#### Solution 2: Create SELinux Policy Module

If you prefer to keep the sendmail transport, create a custom SELinux policy:

```bash
# Check for denials
sudo ausearch -m avc -ts recent | grep sendmail

# Generate policy module
sudo ausearch -c '(sendmail)' --raw | audit2allow -M ywatch-sendmail

# Install the policy
sudo semodule -i ywatch-sendmail.pp

# Verify installation
sudo semodule -l | grep ywatch
```

**When to use:**
- You have specific requirements to use sendmail transport
- You're comfortable managing SELinux policies
- You need the same configuration across multiple servers

**Disadvantages:**
- More complex
- Policy may need updates after system changes
- Less portable

#### Solution 3: Modify Systemd Service SELinux Context

Add specific SELinux capabilities to the systemd service:

```bash
sudo nano /etc/systemd/system/ywatch@.service
```

Add in the `[Service]` section:
```ini
[Service]
# ... existing settings ...

# Allow mail operations
AmbientCapabilities=CAP_SETUID CAP_SETGID
SELinuxContext=system_u:system_r:postfix_postdrop_t:s0
```

Reload and restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart ywatch@monitor.service
```

**When to use:**
- You need sendmail transport for specific reasons
- You don't want to manage separate policy modules

**Disadvantages:**
- Runs ywatch in postfix security context (less isolated)
- May have unintended security implications

## Email Delivery Architecture

### Understanding Localhost SMTP

Setting `smtp_host: "localhost"` does **NOT** limit email to local delivery. Here's how it works:

```
┌─────────────────────────────────────────┐
│  Your Server                            │
│                                         │
│  ywatch → postfix (localhost:25)       │ ← SMTP connection (SELinux-friendly)
│              ↓                          │
│         Internet                        │
│              ↓                          │
│    Remote Email Server                  │
│    (Gmail, Office365, etc.)            │
└─────────────────────────────────────────┘
```

Your local postfix acts as a **mail relay**:
1. ywatch connects to postfix on localhost:25 (SMTP)
2. Postfix queues the message
3. Postfix delivers to the remote email server
4. Remote server delivers to recipient's mailbox

**Verify your postfix can relay:**

```bash
# Check postfix configuration
postconf | grep -E "^(relayhost|inet_interfaces|mydestination)"

# Expected output for send-only server:
# inet_interfaces = localhost        ← Accepts from local apps only
# relayhost =                        ← Empty means direct delivery
# mydestination = ...                ← Local domains
```

**Test email delivery:**

```bash
# Send test email
echo "Test from ywatch server" | mail -s "Test" your-email@example.com

# Watch delivery
sudo tail -f /var/log/maillog
```

If emails don't reach remote addresses, your ISP may be blocking outbound port 25. In that case, configure postfix to use a relay host (smarthost):

```bash
# Example: Use Gmail as relay (requires app password)
sudo postconf -e 'relayhost = [smtp.gmail.com]:587'
sudo postconf -e 'smtp_use_tls = yes'
sudo postconf -e 'smtp_sasl_auth_enable = yes'
# ... plus SASL password configuration
```

## Cleaning the Postfix Queue

If deferred messages accumulated while email was misconfigured:

```bash
# View queued messages
mailq

# Delete all deferred messages
sudo postsuper -d ALL deferred

# Or delete ALL messages (deferred + active)
sudo postsuper -d ALL

# Verify queue is empty
mailq
```

## Troubleshooting

### Diagnostic Commands

```bash
# Check if SELinux is enforcing
getenforce

# View all recent SELinux denials
sudo ausearch -m avc -ts recent

# View ywatch-specific denials
sudo ausearch -m avc -ts recent | grep ywatch

# Check ywatch service status
sudo systemctl status ywatch@monitor.service

# View ywatch logs
sudo journalctl -u ywatch@monitor.service -f

# Check ywatch executable permissions and context
ls -lZ /usr/local/bin/ywatch

# Test postfix email delivery
echo "Test" | mail -s "Test" your-email@example.com
sudo tail -f /var/log/maillog

# Verify SMTP connection to localhost
telnet localhost 25
# Type: QUIT (then Enter)

# Check ywatch configuration
ywatch --config /etc/ywatch/monitor.yml --validate
```

### Common Error Messages

**"Permission denied" executing ywatch:**
- Fix file permissions (chmod 755)
- Set SELinux context (semanage + restorecon)

**"Cannot write to maildrop":**
- Switch to SMTP transport (recommended)
- Or create SELinux policy module

**"Connection refused" to localhost:25:**
- Postfix not running: `sudo systemctl start postfix`
- Check postfix listens on localhost: `sudo ss -tlnp | grep :25`

**Emails stuck in queue (deferred):**
- Check `/var/log/maillog` for delivery errors
- Verify DNS resolution works
- Check if ISP blocks port 25
- May need to configure relay host

### SELinux Troubleshooting Mode

To temporarily disable SELinux for testing (NOT recommended for production):

```bash
# Check current mode
getenforce

# Set to permissive (logs denials but doesn't block)
sudo setenforce 0

# Test your configuration
sudo systemctl restart ywatch@monitor.service

# Re-enable enforcing
sudo setenforce 1

# Make permanent changes in /etc/selinux/config (not recommended)
```

**Important:** Don't run production systems with SELinux disabled. Use proper contexts and policies instead.

## Verification Checklist

After configuration, verify everything works:

- [ ] ywatch service starts successfully
  ```bash
  sudo systemctl start ywatch@monitor.service
  sudo systemctl status ywatch@monitor.service
  ```

- [ ] No SELinux denials in logs
  ```bash
  sudo ausearch -m avc -ts recent | grep ywatch
  # Should return no results
  ```

- [ ] Service remains running (not restarting repeatedly)
  ```bash
  sudo systemctl status ywatch@monitor.service
  # Should show "active (running)"
  ```

- [ ] Email delivery works
  ```bash
  # Trigger a test event or send test email
  mailq  # Should show empty queue or successful delivery
  ```

- [ ] Service logs show normal operation
  ```bash
  sudo journalctl -u ywatch@monitor.service -n 50
  # Should show startup and monitoring activity, no errors
  ```

## Security Considerations

### File Permissions

The ywatch executable should be:
- **Owned by root or trusted user**
- **Permissions: 755** (readable and executable by all, writable only by owner)
- **SELinux context: bin_t**

```bash
sudo chown root:root /usr/local/bin/ywatch
sudo chmod 755 /usr/local/bin/ywatch
sudo semanage fcontext -a -t bin_t "/usr/local/bin/ywatch"
sudo restorecon -v /usr/local/bin/ywatch
```

### Systemd Service Security

The default systemd service includes security hardening:
- `NoNewPrivileges=true` - Prevents privilege escalation
- `PrivateTmp=true` - Uses private /tmp directory

Additional hardening options available (see systemd/README.md):
- `ProtectSystem=strict`
- `ProtectHome=true`
- `PrivateDevices=true`

**Note:** Some hardening options may prevent ywatch from watching certain directories or executing commands. Test thoroughly.

### Email Security

- Use `smtp_host: "localhost"` to keep email traffic local
- Configure postfix to only relay from localhost (`inet_interfaces = localhost`)
- Use authentication if relaying through external SMTP servers
- Implement SPF/DKIM/DMARC for production email sending

## Reference: Complete Working Configuration

Here's a complete working example for Rocky Linux 9:

**File: /etc/ywatch/monitor.yml**
```yaml
---
name: "Production Monitor"
pidfile: "/var/run/ywatch/monitor.pid"

logging:
  level: INFO
  file: "/var/log/ywatch/monitor.log"

email:
  from: "ywatch@localhost"
  smtp_host: "localhost"
  smtp_port: 25

watchlists:
  - name: "config_watch"
    watches:
      - path: "/etc/myapp"
        recursive: true
        events:
          - close_write
        filters:
          include: '\.conf$'
        actions:
          - type: email
            to: "admin@example.com"
            subject: "Config changed: %file%"
            body: |
              Configuration file modified:

              File: %fullpath%
              Time: %timestamp%

          - type: syslog
            priority: info
            facility: local0
            message: "Config file modified: %fullpath%"
```

**File: /etc/systemd/system/ywatch@.service**
```ini
[Unit]
Description=ywatch filesystem monitor - %i
Documentation=man:ywatch.pl(1)
After=network.target

[Service]
Type=simple
User=root
Group=root

# Path to ywatch executable and config
ExecStart=/usr/local/bin/ywatch --config /etc/ywatch/%i.yml
ExecReload=/bin/kill -HUP $MAINPID

# Email configuration for SELinux
Environment="EMAIL_SENDER_TRANSPORT=SMTP"
Environment="EMAIL_SENDER_TRANSPORT_host=localhost"
Environment="EMAIL_SENDER_TRANSPORT_port=25"

# Restart on failure
Restart=always
RestartSec=10

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ywatch-%i

# Security hardening
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

**Setup commands:**
```bash
# Set permissions and SELinux context
sudo chmod 755 /usr/local/bin/ywatch
sudo semanage fcontext -a -t bin_t "/usr/local/bin/ywatch"
sudo restorecon -v /usr/local/bin/ywatch

# Create directories
sudo mkdir -p /etc/ywatch /var/log/ywatch /var/run/ywatch

# Install configuration
sudo cp monitor.yml /etc/ywatch/

# Install and start service
sudo systemctl daemon-reload
sudo systemctl enable ywatch@monitor.service
sudo systemctl start ywatch@monitor.service

# Verify
sudo systemctl status ywatch@monitor.service
sudo journalctl -u ywatch@monitor.service -f
```

## Additional Resources

- **Main README**: See README.md for general ywatch documentation
- **systemd Integration**: See systemd/README.md for detailed systemd configuration
- **SELinux Documentation**: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/using_selinux/
- **Postfix Documentation**: http://www.postfix.org/documentation.html
- **Email::Sender::Simple**: https://metacpan.org/pod/Email::Sender::Simple

## Support

For issues specific to SELinux configuration:
1. Check the Troubleshooting section above
2. Review SELinux audit logs: `sudo ausearch -m avc -ts recent`
3. File an issue: https://github.com/usna78/Linux-Inotify2-WatchDir-Simple/issues

Include in your issue report:
- Linux distribution and version
- SELinux mode (`getenforce`)
- Output of `ls -lZ /usr/local/bin/ywatch`
- Recent SELinux denials (`sudo ausearch -m avc -ts recent | grep ywatch`)
- Service status and logs
