# Shared Services Setup Guide

## Overview

This guide explains how to set up shared services (like MinIO and MailPit) that can be used across multiple projects, similar to how you might have a shared database or Redis instance.

## Shared MinIO Setup

### Quick Start: Shared MinIO

1. **Create a shared MinIO container** (run once):

```bash
# Create directory for shared services
mkdir -p ~/docker-services/minio
cd ~/docker-services/minio

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  minio:
    image: minio/minio:latest
    container_name: minio-shared
    restart: unless-stopped
    ports:
      - "9000:9000"   # S3 API
      - "9001:9001"   # Web console
    environment:
      MINIO_ROOT_USER: ChangeMeMinioUser
      MINIO_ROOT_PASSWORD: ChangeMeMinioPassword123
    volumes:
      - minio_data:/data
    command: server /data --console-address ":9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

volumes:
  minio_data:
EOF

# Start it
docker compose up -d
```

2. **Configure your project to use shared MinIO**:

In your project's `.env` file:
```env
# Do NOT set MINIO_API_PORT (this would include per-project MinIO)
# Instead, point to the shared instance
STORAGE_ENDPOINT=http://host.docker.internal:9000
STORAGE_BUCKET=your-project-bucket
STORAGE_KEY=ChangeMeStorageKey
STORAGE_SECRET=ChangeMeStorageSecret123
```

3. **Create your project's bucket**:

- Access MinIO console: `http://localhost:9001`
- Login: `ChangeMeMinioUser` / `ChangeMeMinioPassword123`
- Create bucket: `your-project-bucket` (or whatever you set in `STORAGE_BUCKET`)

### Per-Project MinIO (Alternative)

If you prefer per-project MinIO:

1. **Add to `.env`**:
```env
MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_ROOT_USER=ChangeMeMinioRootUser
MINIO_ROOT_PASSWORD=ChangeMeMinioRootPassword123
```

2. **The Makefile automatically includes `compose.minio.yaml`** when `MINIO_API_PORT` is set.

## Comparison: Shared vs Per-Project

| Feature | Shared MinIO | Per-Project MinIO |
|---------|-------------|-------------------|
| **Resource Usage** | One container | One per project |
| **Port Conflicts** | None (fixed ports) | Need different ports per project |
| **Management** | One console for all | Separate console per project |
| **Data Isolation** | By bucket name | By container |
| **Setup Complexity** | One-time setup | Per-project setup |
| **Best For** | Multiple projects | Single project or testing |

## Shared MailPit Setup

MailPit already works this way! See `compose.mailer.yaml` for reference.

### Using Existing MailPit

If you have a shared MailPit container running:

In your `.env`:
```env
# Do NOT set MAILPIT_WEB_PORT (this would include per-project MailPit)
# Instead, point to shared instance
MAILER_DSN=smtp://host.docker.internal:1025
```

## Environment Variable Reference

### For Shared MinIO

```env
# External MinIO endpoint
STORAGE_ENDPOINT=http://host.docker.internal:9000

# Your project's bucket (create it in MinIO console)
STORAGE_BUCKET=your-project-name

# MinIO credentials (should match shared MinIO)
STORAGE_KEY=ChangeMeStorageKey
STORAGE_SECRET=ChangeMeStorageSecret123

# S3 region (MinIO ignores this, but required)
STORAGE_REGION=us-east-1
```

### For Per-Project MinIO

```env
# Include per-project MinIO container
MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_ROOT_USER=ChangeMeMinioRootUser
MINIO_ROOT_PASSWORD=ChangeMeMinioRootPassword123
```

## Troubleshooting

### "host.docker.internal" not working (Linux)

On native Linux (not WSL2), `host.docker.internal` might not work. Use:

```env
STORAGE_ENDPOINT=http://172.17.0.1:9000
```

Or find your host IP:
```bash
ip addr show docker0 | grep inet
```

### Port Already in Use

If port 9000 is already used by shared MinIO:

1. **Option 1**: Use shared MinIO (recommended)
   - Remove `MINIO_API_PORT` from `.env`
   - Set `STORAGE_ENDPOINT=http://host.docker.internal:9000`

2. **Option 2**: Use different ports for per-project MinIO
   ```env
   MINIO_API_PORT=9010
   MINIO_CONSOLE_PORT=9011
   ```

### Connection Refused

1. **Check if shared MinIO is running**:
   ```bash
   docker ps | grep minio
   ```

2. **Test connection**:
   ```bash
   curl http://localhost:9000/minio/health/live
   ```

3. **From PHP container**:
   ```bash
   docker compose exec php curl http://host.docker.internal:9000/minio/health/live
   ```

## Benefits of Shared Services

✅ **Resource Efficiency**: One container instead of many  
✅ **Consistent Setup**: Same configuration across projects  
✅ **Centralized Management**: One console/interface for all projects  
✅ **No Port Conflicts**: Fixed ports, no need to change per project  
✅ **Easier Backup**: All data in one place  
✅ **Development Speed**: Start projects faster (no need to start service containers)

## Example: Complete Shared Services Setup

Create `~/docker-services/docker-compose.yml`:

```yaml
version: '3.8'

services:
  minio:
    image: minio/minio:latest
    container_name: minio-shared
    restart: unless-stopped
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: ChangeMeMinioUser
      MINIO_ROOT_PASSWORD: ChangeMeMinioPassword123
    volumes:
      - minio_data:/data
    command: server /data --console-address ":9001"

  mailpit:
    image: axllent/mailpit
    container_name: mailpit-shared
    restart: unless-stopped
    ports:
      - "1025:1025"
      - "8025:8025"
    environment:
      MP_SMTP_AUTH_ACCEPT_ANY: 1
      MP_SMTP_AUTH_ALLOW_INSECURE: 1

volumes:
  minio_data:
```

Start all shared services:
```bash
cd ~/docker-services
docker compose up -d
```

Then configure each project to use them via environment variables.

