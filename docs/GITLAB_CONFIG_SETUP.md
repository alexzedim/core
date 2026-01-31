# GitLab Configuration Setup Guide

## Overview

This guide documents the GitLab configuration storage locations for the self-hosted GitLab instance. The setup has been migrated from environment variable-based configuration to file-based configuration, providing better security, version control, and maintainability.

The GitLab container uses configuration files mounted from the host system, allowing you to manage settings externally from the container while maintaining data persistence across container restarts and updates.

## Directory Structure

The GitLab configuration is organized in the following directory structure:

```
gitlab/
├── config/
│   ├── gitlab.rb              # Main GitLab configuration file
│   └── gitlab-secrets.json    # Sensitive secrets and credentials
├── logs/                      # Container logs directory
├── data/                      # Reference directory (not mounted)
└── .gitignore                 # Git ignore rules
```

### Directory Purposes

- **config/** - Contains all GitLab configuration files that are mounted into the container
- **logs/** - Stores GitLab application and service logs
- **data/** - Reference directory for documentation purposes (not used in container mounts)

## Volume Mounts

The GitLab service in [`docker-compose.git.yml`](../docker-compose.git.yml:147-175) uses the following volume mounts:

| Host Path | Container Path | Mount Mode | Purpose |
|-----------|----------------|-------------|---------|
| `./gitlab/config/gitlab.rb` | `/etc/gitlab/gitlab.rb` | `:ro` (read-only) | Main configuration file |
| `./gitlab/config/gitlab-secrets.json` | `/etc/gitlab/gitlab-secrets.json` | `:ro` (read-only) | Encrypted secrets file |
| `./gitlab/logs` | `/var/log/gitlab` | read/write | Application and service logs |
| `gitlab` (named volume) | `/var/opt/gitlab` | read/write | Persistent data storage |

### Named Volume Configuration

The `gitlab` named volume is configured as a bind mount to `/mnt/gitlab` on the host:

```yaml
volumes:
  gitlab:
    driver: local
    driver_opts:
      type: 'none'
      o: 'bind'
      device: '/mnt/gitlab'
```

This configuration maps the host directory `/mnt/gitlab` to the container's `/var/opt/gitlab`, providing direct access to GitLab data from the host system.

## Configuration Files

### gitlab.rb

**Location:** `./gitlab/config/gitlab.rb` → `/etc/gitlab/gitlab.rb`

The [`gitlab.rb`](../gitlab/config/gitlab.rb) file is the main configuration file for GitLab. It contains all non-sensitive settings such as:

- External URL and domain configuration
- Database connection settings
- Redis connection settings
- Email server configuration
- Backup settings
- Application settings (timeouts, limits, etc.)
- Service-specific configurations (nginx, postgresql, etc.)

#### How to Edit gitlab.rb

1. Open the file in your preferred editor:
   ```bash
   nano ./gitlab/config/gitlab.rb
   ```

2. Modify the desired configuration parameters. Most settings follow this pattern:
   ```ruby
   external_url 'https://gitlab.example.com'
   gitlab_rails['time_zone'] = 'UTC'
   ```

3. Save the file

4. Apply the changes (see [Configuration Changes](#configuration-changes) section)

**Important:** The file is mounted as read-only (`:ro`) in the container. This is intentional to prevent the container from modifying your configuration files. Always edit the host-side file.

### gitlab-secrets.json

**Location:** `./gitlab/config/gitlab-secrets.json` → `/etc/gitlab/gitlab-secrets.json`

The [`gitlab-secrets.json`](../gitlab/config/gitlab-secrets.json) file contains sensitive information such as:

- Database passwords
- Redis passwords
- Secret keys (db_key_base, otp_key_base, etc.)
- Initial root password
- Third-party service credentials
- Encryption keys

#### Security Considerations

**⚠️ CRITICAL SECURITY WARNING:**

- **Never commit** `gitlab-secrets.json` to version control
- This file is already included in [`.gitignore`](../gitlab/.gitignore)
- Store backups in a secure, encrypted location
- Restrict file permissions to read-only for the container user
- Rotate secrets periodically
- Use strong, unique passwords and keys

#### File Permissions

Set restrictive permissions on the secrets file:

```bash
chmod 600 ./gitlab/config/gitlab-secrets.json
chown root:root ./gitlab/config/gitlab-secrets.json
```

## Storage Locations

### Configuration Files

**Host Path:** `./gitlab/config/`
**Container Path:** `/etc/gitlab/`

All configuration files should be stored in the `./gitlab/config/` directory. This directory is mounted read-only into the container, ensuring that:

- Configuration changes require explicit action
- The container cannot accidentally modify your configuration
- Configuration is preserved across container recreation

### Logs

**Host Path:** `./gitlab/logs/`
**Container Path:** `/var/log/gitlab`

GitLab logs are stored in the `./gitlab/logs/` directory. This includes:

- `gitlab-rails/` - Application logs
- `gitlab-workhorse/` - Workhorse proxy logs
- `nginx/` - Web server logs
- `postgresql/` - Database logs
- `redis/` - Redis logs
- `sidekiq/` - Background job logs

**Log Rotation:** Configure log rotation in [`gitlab.rb`](../gitlab/config/gitlab.rb) to prevent disk space issues:

```ruby
logging['logrotate_frequency'] = 'daily'
logging['logrotate_rotate'] = 30
```

### Data

**Host Path:** `/mnt/gitlab`
**Container Path:** `/var/opt/gitlab`

All persistent GitLab data is stored in `/mnt/gitlab` on the host system. This includes:

- Repository data
- Database files
- User uploads and attachments
- Backup files
- LFS objects
- Container registry data
- Packages and dependencies

**Note:** The `gitlab/data/` directory in the project is for reference only and is **not** mounted to the container.

## Security Best Practices

### Protecting gitlab-secrets.json

1. **Version Control:** Ensure `gitlab-secrets.json` is in [`.gitignore`](../gitlab/.gitignore)
2. **File Permissions:** Restrict to `600` (read/write for owner only)
3. **Access Control:** Limit access to authorized administrators only
4. **Backups:** Encrypt backups containing secrets files
5. **Rotation:** Establish a schedule for rotating secrets
6. **Monitoring:** Monitor for unauthorized access attempts

### File Permissions Recommendations

```bash
# Configuration directory
chmod 755 ./gitlab/config/

# Main configuration file
chmod 644 ./gitlab/config/gitlab.rb

# Secrets file (most restrictive)
chmod 600 ./gitlab/config/gitlab-secrets.json

# Logs directory
chmod 755 ./gitlab/logs/
```

### Version Control Guidelines

**✅ Commit to Version Control:**
- `gitlab.rb` - Contains non-sensitive configuration
- `.gitignore` - Ensures secrets are not committed
- Configuration templates or examples
- Documentation files

**❌ Do NOT Commit:**
- `gitlab-secrets.json` - Contains sensitive credentials
- Any files with passwords, tokens, or keys
- Unencrypted backup files
- Production-specific secrets

### Environment Variables

While this setup uses configuration files instead of environment variables, you may still need to use environment variables for:

- Database connection strings (if external)
- External service credentials
- Container orchestration settings

Store these in a `.env` file and add it to `.gitignore`:

```bash
# .env
GITHUB_TOKEN=your_token_here
```

## Configuration Changes

### Applying Changes

After modifying [`gitlab.rb`](../gitlab/config/gitlab.rb), follow these steps to apply changes:

#### Option 1: Restart the Container

```bash
docker-compose -f docker-compose.git.yml restart gitlab
```

This is the simplest method and works for most configuration changes.

#### Option 2: Run gitlab-ctl Reconfigure

For more complex changes or when you need to reconfigure services:

```bash
# Enter the container
docker exec -it gitlab bash

# Run reconfigure
gitlab-ctl reconfigure

# Exit the container
exit
```

The `gitlab-ctl reconfigure` command applies all configuration changes and restarts affected services.

### When to Use Each Method

- **Restart:** Use for simple changes like timeouts, limits, or feature flags
- **Reconfigure:** Use for structural changes like:
  - Adding/removing services
  - Changing database or Redis settings
  - Modifying external URLs
  - Enabling/disabling major features

### Verifying Changes

After applying changes, verify that GitLab is running correctly:

```bash
# Check container status
docker ps | grep gitlab

# View logs
docker logs gitlab

# Check GitLab service status
docker exec -it gitlab gitlab-ctl status
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Configuration Not Applied

**Symptoms:** Changes to [`gitlab.rb`](../gitlab/config/gitlab.rb) don't take effect.

**Solutions:**
- Ensure you've restarted the container or run `gitlab-ctl reconfigure`
- Check for syntax errors in the configuration file
- Verify the file is properly mounted: `docker exec gitlab cat /etc/gitlab/gitlab.rb`

#### 2. Container Won't Start

**Symptoms:** Container exits immediately after starting.

**Solutions:**
- Check container logs: `docker logs gitlab`
- Verify configuration file syntax
- Ensure `gitlab-secrets.json` exists and is properly formatted
- Check volume mount permissions

#### 3. Permission Denied Errors

**Symptoms:** Container cannot read configuration files.

**Solutions:**
- Verify file permissions on host system
- Ensure the container user has read access
- Check SELinux/AppArmor contexts if applicable

#### 4. Secrets File Issues

**Symptoms:** Authentication failures or encryption errors.

**Solutions:**
- Verify `gitlab-secrets.json` is valid JSON
- Ensure all required secrets are present
- Check that the file is not corrupted
- Re-generate secrets if necessary (backup first!)

#### 5. Log Directory Issues

**Symptoms:** Application logs not appearing in `./gitlab/logs/`.

**Solutions:**
- Verify the mount is working: `docker exec gitlab ls -la /var/log/gitlab`
- Check directory permissions: `ls -la ./gitlab/logs/`
- Ensure the container has write access to the logs directory

#### 6. Data Persistence Issues

**Symptoms:** Data lost after container recreation.

**Solutions:**
- Verify the named volume is properly mounted: `docker volume inspect gitlab`
- Check that `/mnt/gitlab` exists on the host
- Ensure the volume has sufficient disk space
- Verify the bind mount configuration in `docker-compose.git.yml`

### Debugging Commands

```bash
# Check container status
docker-compose -f docker-compose.git.yml ps gitlab

# View recent logs
docker logs --tail 100 gitlab

# Follow logs in real-time
docker logs -f gitlab

# Check mounted volumes
docker inspect gitlab | grep -A 10 Mounts

# Enter container for debugging
docker exec -it gitlab bash

# Check GitLab service status
docker exec -it gitlab gitlab-ctl status

# View GitLab configuration
docker exec -it gitlab gitlab-ctl show-config

# Check disk usage
docker exec -it gitlab df -h
```

## Quick Reference

### File Locations Summary

| File/Directory | Host Path | Container Path | Purpose | Mode |
|----------------|-----------|----------------|---------|------|
| Main Config | `./gitlab/config/gitlab.rb` | `/etc/gitlab/gitlab.rb` | Configuration settings | Read-only |
| Secrets | `./gitlab/config/gitlab-secrets.json` | `/etc/gitlab/gitlab-secrets.json` | Sensitive credentials | Read-only |
| Logs | `./gitlab/logs/` | `/var/log/gitlab` | Application logs | Read/write |
| Data | `/mnt/gitlab` | `/var/opt/gitlab` | Persistent data | Read/write |

### Common Commands

```bash
# Start GitLab
docker-compose -f docker-compose.git.yml up -d gitlab

# Stop GitLab
docker-compose -f docker-compose.git.yml stop gitlab

# Restart GitLab
docker-compose -f docker-compose.git.yml restart gitlab

# View logs
docker logs -f gitlab

# Apply configuration changes
docker exec -it gitlab gitlab-ctl reconfigure

# Check service status
docker exec -it gitlab gitlab-ctl status

# Backup configuration
tar -czf gitlab-config-backup-$(date +%Y%m%d).tar.gz ./gitlab/config/
```

### Important Notes

- ⚠️ **Never commit** `gitlab-secrets.json` to version control
- 📝 Always backup configuration files before making changes
- 🔒 Use restrictive file permissions for secrets (600)
- 🔄 Restart the container after configuration changes
- 📊 Monitor disk usage in `/mnt/gitlab` and `./gitlab/logs/`
- 🛡️ Regularly rotate secrets and passwords
- 📖 Refer to the [official GitLab documentation](https://docs.gitlab.com/omnibus/settings/configuration.html) for advanced configuration options

## Additional Resources

- [GitLab Omnibus Configuration Documentation](https://docs.gitlab.com/omnibus/settings/configuration.html)
- [GitLab Secrets Management](https://docs.gitlab.com/omnibus/settings/secrets.html)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [GitLab Backup and Restore](https://docs.gitlab.com/ee/raketasks/backup_restore.html)

---

**Last Updated:** 2026-01-31

For questions or issues related to this configuration, refer to the troubleshooting section or consult the official GitLab documentation.
