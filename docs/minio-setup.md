# MinIO Storage Setup Guide

## Overview

MinIO is an S3-compatible object storage service used for local development. You can configure it in two ways:

1. **Per-Project MinIO** - Each project has its own MinIO container (default)
2. **Shared MinIO** - One MinIO instance shared across all projects (recommended)

## Option 1: Per-Project MinIO (Default)

Each project runs its own MinIO container. This is the default behavior.

### Setup

1. Add to your `.env` file:
```env
MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_ROOT_USER=velogrid
MINIO_ROOT_PASSWORD=velogrid123
```

2. The Makefile will automatically include `compose.storage.yaml` when `MINIO_API_PORT` is set.

3. Start your project:
```bash
make up
```

### Access

- **S3 API**: `http://localhost:9000`
- **Web Console**: `http://localhost:9001`
- **Login**: Use `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` from `.env`

## Option 2: Shared MinIO (Recommended)

Use one MinIO instance for all your projects, similar to how MailPit works.

### Setup Shared MinIO Container

1. **Create a shared MinIO container** (run once, outside any project):

```bash
docker run -d \
  --name minio-shared \
  --restart unless-stopped \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=velogrid \
  -e MINIO_ROOT_PASSWORD=velogrid123 \
  -v minio-shared-data:/data \
  minio/minio:latest server /data --console-address ":9001"
```

Or create a `docker-compose.yml` in a shared location (e.g., `~/docker-services/minio/docker-compose.yml`):

```yaml
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
      MINIO_ROOT_USER: velogrid
      MINIO_ROOT_PASSWORD: velogrid123
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
```

Then start it:
```bash
cd ~/docker-services/minio
docker compose up -d
```

### Configure Projects to Use Shared MinIO

In each project's `.env` file, **do NOT set** `MINIO_API_PORT` (this prevents including the per-project MinIO), and configure the endpoint:

```env
# Use external shared MinIO
STORAGE_ENDPOINT=http://host.docker.internal:9000
STORAGE_BUCKET=your-project-name
STORAGE_REGION=us-east-1
STORAGE_KEY=velogrid
STORAGE_SECRET=velogrid123
```

**Note**: 
- On Linux/WSL2, use `host.docker.internal` (Docker Desktop handles this)
- On native Linux, you might need to use `172.17.0.1` or the host's IP
- Ensure the shared MinIO container is running before starting your project

### Benefits of Shared MinIO

✅ **Resource Efficiency**: One container instead of one per project  
✅ **Consistent Configuration**: Same credentials and setup across projects  
✅ **Centralized Management**: One console to manage all buckets  
✅ **Port Conflicts**: Avoid port conflicts between projects  
✅ **Data Persistence**: All data in one place, easier to backup

## Bucket Management

### Creating Buckets

Each project should use its own bucket. Create buckets via:

1. **Web Console**: `http://localhost:9001` → Login → Create Bucket
2. **Command Line**:
```bash
# Using MinIO client (mc)
docker run --rm -it --network host minio/mc alias set local http://localhost:9000 velogrid velogrid123
docker run --rm -it --network host minio/mc mb local/your-bucket-name
```

### Bucket Naming Convention

Use project-specific bucket names:
- `velogrid-rides` - For velogrid project
- `project2-uploads` - For another project
- `project3-media` - For another project

This keeps data isolated per project while sharing the MinIO instance.

## Environment Variables

### Required for External MinIO

```env
# External MinIO endpoint (when using shared MinIO)
STORAGE_ENDPOINT=http://host.docker.internal:9000

# Your project's bucket name
STORAGE_BUCKET=velogrid-rides

# S3 region (MinIO ignores this, but required by AWS SDK)
STORAGE_REGION=us-east-1

# MinIO credentials (should match shared MinIO)
STORAGE_KEY=velogrid
STORAGE_SECRET=velogrid123
```

### Optional for Per-Project MinIO

```env
# Include per-project MinIO container
MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_ROOT_USER=velogrid
MINIO_ROOT_PASSWORD=velogrid123
```

## Troubleshooting

### Connection Issues with External MinIO

**Problem**: Can't connect to `host.docker.internal:9000`

**Solutions**:

1. **On Linux (native)**: Use the host's IP address:
   ```env
   STORAGE_ENDPOINT=http://172.17.0.1:9000
   ```

2. **Check if MinIO is running**:
   ```bash
   docker ps | grep minio
   ```

3. **Test connection from PHP container**:
   ```bash
   docker compose exec php curl http://host.docker.internal:9000/minio/health/live
   ```

4. **Use Docker network**: If both containers are in the same Docker network, use the container name:
   ```env
   STORAGE_ENDPOINT=http://minio-shared:9000
   ```

### Port Conflicts

**Problem**: Port 9000 or 9001 already in use

**Solutions**:

1. **Use different ports for shared MinIO**:
   ```bash
   docker run -d \
     -p 9010:9000 \  # Different API port
     -p 9011:9001 \  # Different console port
     ...
   ```

2. **Update project's `.env`**:
   ```env
   STORAGE_ENDPOINT=http://host.docker.internal:9010
   ```

### Bucket Not Found

**Problem**: `NoSuchBucket` error

**Solution**: Create the bucket first:
1. Access MinIO console: `http://localhost:9001`
2. Login with credentials
3. Click "Create Bucket"
4. Enter bucket name (must match `STORAGE_BUCKET` in `.env`)

## Migration from Per-Project to Shared MinIO

If you've been using per-project MinIO and want to switch to shared:

1. **Export data from project MinIO** (if needed):
   ```bash
   # Access project's MinIO container
   docker compose exec minio mc mirror /data/bucket-name ./backup/
   ```

2. **Start shared MinIO** (see setup above)

3. **Create bucket in shared MinIO** with the same name

4. **Import data** (if needed):
   ```bash
   docker run --rm -it -v $(pwd)/backup:/backup minio/mc \
     mirror /backup local/shared-bucket-name
   ```

5. **Update project's `.env`**:
   - Remove `MINIO_API_PORT` (to disable per-project MinIO)
   - Set `STORAGE_ENDPOINT=http://host.docker.internal:9000`

6. **Restart project**:
   ```bash
   make down
   make up
   ```

## Best Practices

1. **Use Shared MinIO for Development**: Saves resources and simplifies management
2. **Per-Project Buckets**: Each project should have its own bucket
3. **Naming Convention**: Use descriptive bucket names (e.g., `project-name-purpose`)
4. **Credentials**: Use the same credentials for shared MinIO across all projects
5. **Backup**: Regularly backup the shared MinIO data volume
6. **Production**: Use cloud storage (Scaleway, AWS S3, etc.) in production, not MinIO

## Example: Complete Setup Script

Create `~/docker-services/minio/start.sh`:

```bash
#!/bin/bash

# Start shared MinIO for all projects
docker compose up -d

echo "MinIO started!"
echo "S3 API: http://localhost:9000"
echo "Console: http://localhost:9001"
echo "User: velogrid"
echo "Password: velogrid123"
```

Make it executable:
```bash
chmod +x ~/docker-services/minio/start.sh
```

Run it once to start shared MinIO for all your projects.

# MinIO Storage Setup Guide

## Overview

MinIO is an S3-compatible object storage service used for local development. You can configure it in two ways:

1. **Per-Project MinIO** - Each project has its own MinIO container (default)
2. **Shared MinIO** - One MinIO instance shared across all projects (recommended)

## Option 1: Per-Project MinIO (Default)

Each project runs its own MinIO container. This is the default behavior.

### Setup

1. Add to your `.env` file:
```env
MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_ROOT_USER=velogrid
MINIO_ROOT_PASSWORD=velogrid123
```

2. The Makefile will automatically include `compose.storage.yaml` when `MINIO_API_PORT` is set.

3. Start your project:
```bash
make up
```

### Access

- **S3 API**: `http://localhost:9000`
- **Web Console**: `http://localhost:9001`
- **Login**: Use `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` from `.env`

## Option 2: Shared MinIO (Recommended)

Use one MinIO instance for all your projects, similar to how MailPit works.

### Setup Shared MinIO Container

1. **Create a shared MinIO container** (run once, outside any project):

```bash
docker run -d \
  --name minio-shared \
  --restart unless-stopped \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=velogrid \
  -e MINIO_ROOT_PASSWORD=velogrid123 \
  -v minio-shared-data:/data \
  minio/minio:latest server /data --console-address ":9001"
```

Or create a `docker-compose.yml` in a shared location (e.g., `~/docker-services/minio/docker-compose.yml`):

```yaml
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
      MINIO_ROOT_USER: velogrid
      MINIO_ROOT_PASSWORD: velogrid123
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
```

Then start it:
```bash
cd ~/docker-services/minio
docker compose up -d
```

### Configure Projects to Use Shared MinIO

In each project's `.env` file, **do NOT set** `MINIO_API_PORT` (this prevents including the per-project MinIO), and configure the endpoint:

```env
# Use external shared MinIO
STORAGE_ENDPOINT=http://host.docker.internal:9000
STORAGE_BUCKET=your-project-name
STORAGE_REGION=us-east-1
STORAGE_KEY=velogrid
STORAGE_SECRET=velogrid123
```

**Note**: 
- On Linux/WSL2, use `host.docker.internal` (Docker Desktop handles this)
- On native Linux, you might need to use `172.17.0.1` or the host's IP
- Ensure the shared MinIO container is running before starting your project

### Benefits of Shared MinIO

✅ **Resource Efficiency**: One container instead of one per project  
✅ **Consistent Configuration**: Same credentials and setup across projects  
✅ **Centralized Management**: One console to manage all buckets  
✅ **Port Conflicts**: Avoid port conflicts between projects  
✅ **Data Persistence**: All data in one place, easier to backup

## Bucket Management

### Creating Buckets

Each project should use its own bucket. Create buckets via:

1. **Web Console**: `http://localhost:9001` → Login → Create Bucket
2. **Command Line**:
```bash
# Using MinIO client (mc)
docker run --rm -it --network host minio/mc alias set local http://localhost:9000 velogrid velogrid123
docker run --rm -it --network host minio/mc mb local/your-bucket-name
```

### Bucket Naming Convention

Use project-specific bucket names:
- `velogrid-rides` - For velogrid project
- `project2-uploads` - For another project
- `project3-media` - For another project

This keeps data isolated per project while sharing the MinIO instance.

## Environment Variables

### Required for External MinIO

```env
# External MinIO endpoint (when using shared MinIO)
STORAGE_ENDPOINT=http://host.docker.internal:9000

# Your project's bucket name
STORAGE_BUCKET=velogrid-rides

# S3 region (MinIO ignores this, but required by AWS SDK)
STORAGE_REGION=us-east-1

# MinIO credentials (should match shared MinIO)
STORAGE_KEY=velogrid
STORAGE_SECRET=velogrid123
```

### Optional for Per-Project MinIO

```env
# Include per-project MinIO container
MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_ROOT_USER=velogrid
MINIO_ROOT_PASSWORD=velogrid123
```

## Troubleshooting

### Connection Issues with External MinIO

**Problem**: Can't connect to `host.docker.internal:9000`

**Solutions**:

1. **On Linux (native)**: Use the host's IP address:
   ```env
   STORAGE_ENDPOINT=http://172.17.0.1:9000
   ```

2. **Check if MinIO is running**:
   ```bash
   docker ps | grep minio
   ```

3. **Test connection from PHP container**:
   ```bash
   docker compose exec php curl http://host.docker.internal:9000/minio/health/live
   ```

4. **Use Docker network**: If both containers are in the same Docker network, use the container name:
   ```env
   STORAGE_ENDPOINT=http://minio-shared:9000
   ```

### Port Conflicts

**Problem**: Port 9000 or 9001 already in use

**Solutions**:

1. **Use different ports for shared MinIO**:
   ```bash
   docker run -d \
     -p 9010:9000 \  # Different API port
     -p 9011:9001 \  # Different console port
     ...
   ```

2. **Update project's `.env`**:
   ```env
   STORAGE_ENDPOINT=http://host.docker.internal:9010
   ```

### Bucket Not Found

**Problem**: `NoSuchBucket` error

**Solution**: Create the bucket first:
1. Access MinIO console: `http://localhost:9001`
2. Login with credentials
3. Click "Create Bucket"
4. Enter bucket name (must match `STORAGE_BUCKET` in `.env`)

## Migration from Per-Project to Shared MinIO

If you've been using per-project MinIO and want to switch to shared:

1. **Export data from project MinIO** (if needed):
   ```bash
   # Access project's MinIO container
   docker compose exec minio mc mirror /data/bucket-name ./backup/
   ```

2. **Start shared MinIO** (see setup above)

3. **Create bucket in shared MinIO** with the same name

4. **Import data** (if needed):
   ```bash
   docker run --rm -it -v $(pwd)/backup:/backup minio/mc \
     mirror /backup local/shared-bucket-name
   ```

5. **Update project's `.env`**:
   - Remove `MINIO_API_PORT` (to disable per-project MinIO)
   - Set `STORAGE_ENDPOINT=http://host.docker.internal:9000`

6. **Restart project**:
   ```bash
   make down
   make up
   ```

## Best Practices

1. **Use Shared MinIO for Development**: Saves resources and simplifies management
2. **Per-Project Buckets**: Each project should have its own bucket
3. **Naming Convention**: Use descriptive bucket names (e.g., `project-name-purpose`)
4. **Credentials**: Use the same credentials for shared MinIO across all projects
5. **Backup**: Regularly backup the shared MinIO data volume
6. **Production**: Use cloud storage (Scaleway, AWS S3, etc.) in production, not MinIO

## Example: Complete Setup Script

Create `~/docker-services/minio/start.sh`:

```bash
#!/bin/bash

# Start shared MinIO for all projects
docker compose up -d

echo "MinIO started!"
echo "S3 API: http://localhost:9000"
echo "Console: http://localhost:9001"
echo "User: velogrid"
echo "Password: velogrid123"
```

Make it executable:
```bash
chmod +x ~/docker-services/minio/start.sh
```

Run it once to start shared MinIO for all your projects.

