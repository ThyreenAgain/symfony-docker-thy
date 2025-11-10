# Optional Features - Modular Docker Compose Architecture

## Overview

This symfony-docker template uses a **modular architecture** for optional features. Instead of including everything by default, you can choose which features to enable during setup. This keeps your development environment clean and focused on what you actually need.

## Architecture

The project uses multiple Docker Compose files that can be combined:

- **`compose.yaml`** - Core services (PHP, Database) - Always included
- **`compose.override.yaml`** - Development overrides - Auto-loaded in dev
- **`compose.mailer.yaml`** - Optional: Mailpit email testing service
- **`compose.mercure.yaml`** - Optional: Mercure real-time messaging

## Available Features

### 📧 Mailer (Mailpit)

**What it does:**
- Catches all outgoing emails in development
- Provides web UI to view and test emails
- No emails accidentally sent to real addresses

**When to enable:**
- Your app sends emails (registration, notifications, etc.)
- You need to test email templates
- You want to debug email functionality

**Ports:**
- SMTP: 1025 (your app sends emails here)
- Web UI: 8025 (view emails in browser)

**How to use:**
```php
// Symfony automatically uses this in development
// No code changes needed!
```

Access web UI: `http://localhost:8025`

#### 💡 Sharing Mailpit Across Multiple Projects

**Mailpit is stateless** - unlike a database, it doesn't store project-specific data. You can use **ONE shared Mailpit instance** for ALL your projects!

**Benefits:**
- ✅ Use less Docker resources (memory, CPU)
- ✅ No port conflicts when running multiple projects
- ✅ See emails from all projects in one place
- ✅ Simpler setup

**How to share:**

1. **Run ONE Mailpit container** (standalone or from one project):
   ```bash
   # Standalone Mailpit (recommended)
   docker run -d --name mailpit \
     -p 1025:1025 \
     -p 8025:8025 \
     --restart unless-stopped \
     axllent/mailpit
   ```

2. **Configure ALL projects to use it:**
   ```bash
   # In each project's .env.dev.local
   MAILER_DSN=smtp://host.docker.internal:1025
   ```

3. **Skip Mailpit during setup:**
   - When setup.sh asks "Enable Mailer/Mailpit?", answer **n** (no)
   - Manually add to `.env.dev.local`: `MAILER_DSN=smtp://host.docker.internal:1025`

**Important Note:** Use `host.docker.internal` (not `localhost`) to access the host's Mailpit from inside Docker containers.

**Example - Your current setup:**
```
You have: mailer-1 (63309:1025) from "Cycling" project
Solution: Skip Mailpit in new projects, configure:
         MAILER_DSN=smtp://host.docker.internal:63309
```

### ⚡ Mercure Hub

**What it does:**
- Enables real-time communication (Server-Sent Events)
- Push updates to browsers without polling
- Built into FrankenPHP (no separate service)

**When to enable:**
- Building chat applications
- Live notifications or updates
- Real-time dashboards
- Collaborative features

**How to use:**
```bash
# Install the bundle
composer require symfony/mercure-bundle

# Use in your code
$this->hub->publish(new Update('topic', 'data'));
```

## Setup: Enabling Features

### During Initial Setup

The `setup.sh` script will ask you:

```bash
📧 Mailer (Mailpit):
   Email testing service with web UI to catch and inspect emails.
   Enable Mailer/Mailpit? (y/n, default: y): y

⚡ Mercure Hub:
   Real-time messaging for live updates (Server-Sent Events).
   Enable Mercure? (y/n, default: n): n
```

The script will:
1. Create appropriate `.env` configuration
2. Include the optional compose files
3. Start only the services you need

## Manual Management

### Adding a Feature Later

#### 1. Update your `.env` file

**For Mailer:**
```bash
# Add to .env
MAILPIT_SMTP_PORT=1025
MAILPIT_WEB_PORT=8025
```

**For Mercure:**
```bash
# Add to .env
CADDY_MERCURE_JWT_SECRET=!ChangeThisMercureHubJWTSecretKey!
CADDY_MERCURE_URL=http://php/.well-known/mercure
CADDY_MERCURE_PUBLIC_URL=https://localhost:443/.well-known/mercure
```

#### 2. Start with the additional compose file

**With Docker Compose directly:**
```bash
# Add Mailer
docker compose -f compose.yaml -f compose.override.yaml -f compose.mailer.yaml up -d

# Add Mercure
docker compose -f compose.yaml -f compose.override.yaml -f compose.mercure.yaml up -d

# Add both
docker compose -f compose.yaml -f compose.override.yaml -f compose.mailer.yaml -f compose.mercure.yaml up -d
```

**Using Makefile:** (Update needed - see below)
```bash
# Rebuild with new features
make down
# Update compose command in Makefile
make up
```

### Removing a Feature

#### 1. Stop containers
```bash
docker compose -f compose.yaml -f compose.override.yaml -f compose.mailer.yaml down
```

#### 2. Remove from `.env`
```bash
# Comment out or remove the feature's configuration
```

#### 3. Restart without that compose file
```bash
docker compose up -d
```

## Understanding the Files

### compose.mailer.yaml

```yaml
services:
  mailer:
    image: axllent/mailpit  # Lightweight email catcher
    ports:
      - "${MAILPIT_SMTP_PORT:-1025}:1025"  # SMTP port
      - "${MAILPIT_WEB_PORT:-8025}:8025"   # Web UI port
    environment:
      MP_SMTP_AUTH_ACCEPT_ANY: 1           # Accept any auth
```

**What happens:**
- Mailpit service starts
- PHP service gets `MAILER_DSN` environment variable
- Symfony automatically sends emails to Mailpit

### compose.mercure.yaml

```yaml
services:
  php:
    environment:
      # Mercure configuration injected into PHP container
      MERCURE_PUBLISHER_JWT_KEY: ${CADDY_MERCURE_JWT_SECRET}
      MERCURE_SUBSCRIBER_JWT_KEY: ${CADDY_MERCURE_JWT_SECRET}
      MERCURE_URL: ${CADDY_MERCURE_URL}
      MERCURE_PUBLIC_URL: ${CADDY_MERCURE_PUBLIC_URL}
      MERCURE_JWT_SECRET: ${CADDY_MERCURE_JWT_SECRET}
```

**What happens:**
- Environment variables configured for Mercure
- FrankenPHP's built-in Mercure hub activated
- No separate service needed

## Reference File: .dockercompose

After setup, you'll find a `.dockercompose` file listing which compose files are active:

```yaml
version: '3'
files:
  - compose.yaml
  - compose.override.yaml
  - compose.mailer.yaml  # If enabled
  - compose.mercure.yaml # If enabled
```

This is for reference only - it doesn't affect Docker Compose.

## Best Practices

### Start Small
- Begin with just the features you need
- Add more as your project grows
- Avoid "just in case" features

### Development vs Production
- **Development**: Use `compose.override.yaml` with optional features
- **Production**: Use `compose.prod.yaml` without dev tools
- Mailer is typically dev-only
- Mercure can be used in production if needed

### Testing Features
```bash
# Test Mailer
make sf c="messenger:consume async"  # If using async messages
# Send a test email through your app
# Visit http://localhost:8025

# Test Mercure
composer require symfony/mercure-bundle
make sf c="debug:config mercure"
```

## Troubleshooting

### "Service 'mailer' not found"
- You're trying to use Mailer but didn't include `compose.mailer.yaml`
- Solution: Add the compose file to your docker compose command

### Mercure not working
- Check that environment variables are set in `.env`
- Verify `compose.mercure.yaml` is included
- Install `symfony/mercure-bundle`

### Port conflicts
- Mailpit ports (1025, 8025) might be in use
- Change in `.env`: `MAILPIT_SMTP_PORT=2025` and `MAILPIT_WEB_PORT=9025`
- Restart services

## Examples

### Minimal Setup (No Optional Features)
```bash
# Just core services
docker compose up -d
```

### Full Development Setup
```bash
# All features enabled
docker compose \
  -f compose.yaml \
  -f compose.override.yaml \
  -f compose.mailer.yaml \
  -f compose.mercure.yaml \
  up -d
```

### Production Setup
```bash
# Only what's needed for production
docker compose \
  -f compose.yaml \
  -f compose.prod.yaml \
  -f compose.mercure.yaml \
  up -d
```

## Benefits of This Approach

✅ **Cleaner dev environment** - Only run what you need
✅ **Faster startup** - Fewer containers to build and start
✅ **Less resource usage** - Save memory and CPU
✅ **Explicit dependencies** - Clear what your project uses
✅ **Easier to understand** - New developers see relevant services only
✅ **Follows Docker best practices** - Modular, composable architecture

## Migration from All-Inclusive Setup

If you used an older version with everything included:

1. **Identify what you actually use**
   - Do you send emails? Keep mailer
   - Do you use real-time features? Keep mercure
   - Otherwise, remove them

2. **Update your docker compose commands**
   - Add `-f compose.mailer.yaml` if needed
   - Add `-f compose.mercure.yaml` if needed

3. **Update documentation**
   - Tell team members about the new approach
   - Update README with correct docker compose commands

4. **Test thoroughly**
   - Verify all features still work
   - Check that removed services aren't needed

## Further Reading

- [Docker Compose Multiple Files](https://docs.docker.com/compose/multiple-compose-files/)
- [Symfony Mailer](https://symfony.com/doc/current/mailer.html)
- [Symfony Mercure](https://symfony.com/doc/current/mercure.html)
- [FrankenPHP Documentation](https://frankenphp.dev/)