# Database Selection Feature - Architecture Plan

## Overview
Add user-selectable database support (None, MySQL, PostgreSQL, PostGIS) following the existing Mercure modular pattern.

## Current Issues
1. [`compose.yaml`](compose.yaml:46) has duplicate database services (MySQL at line 46, PostGIS at line 61)
2. No mechanism to choose database type during setup
3. [`Makefile`](Makefile:25) hardcodes compose files instead of using variables
4. Environment variables only support MySQL

## Architecture Design

### 1. Database Selection Flow

```mermaid
graph TD
    A[Start Setup] --> B[Ask: Install Database?]
    B -->|No| C[DB_TYPE=none]
    B -->|Yes| D[Ask: Which Database?]
    D --> E[MySQL]
    D --> F[PostgreSQL]
    D --> G[PostGIS]
    E --> H[Configure MySQL Ports/Creds]
    F --> I[Configure PostgreSQL Ports/Creds]
    G --> J[Configure PostGIS Ports/Creds]
    H --> K[Write DB_TYPE=mysql to .env]
    I --> L[Write DB_TYPE=postgres to .env]
    J --> M[Write DB_TYPE=postgis to .env]
    C --> N[Continue Setup]
    K --> N
    L --> N
    M --> N
```

### 2. File Changes Required

#### A. [`setup/setup.sh`](setup/setup.sh:1) Changes

**Location:** After line 308 (Optional Features section)

```bash
# --- Database Selection ---
echo "--- Database Configuration ---"
echoc "36" "📊 Database Selection:"
echoc "36" "   Choose which database to install (if any)."
echo ""

read -p "   Do you want to install a database? (y/n, default: y): " WANT_DATABASE
WANT_DATABASE=$(echo "${WANT_DATABASE:-y}" | tr '[:upper:]' '[:lower:]')
echo ""

DB_TYPE="none"
if [[ "$WANT_DATABASE" == "y" ]]; then
    echoc "36" "   Select database type:"
    echoc "36" "   1. MySQL (default)"
    echoc "36" "   2. PostgreSQL"
    echoc "36" "   3. PostGIS (PostgreSQL with spatial extensions)"
    echo ""
    read -p "   Enter choice (1-3, default: 1): " DB_CHOICE
    DB_CHOICE=${DB_CHOICE:-1}
    
    case $DB_CHOICE in
        1)
            DB_TYPE="mysql"
            echoc "32" "   ✓ Selected: MySQL"
            ;;
        2)
            DB_TYPE="postgres"
            echoc "32" "   ✓ Selected: PostgreSQL"
            ;;
        3)
            DB_TYPE="postgis"
            echoc "32" "   ✓ Selected: PostGIS"
            ;;
        *)
            echoc "31" "   Invalid choice. Defaulting to MySQL."
            DB_TYPE="mysql"
            ;;
    esac
else
    echoc "36" "   No database will be installed."
fi
echo ""
```

**Database Credentials Section Updates:**

```bash
# --- Get DB Credentials (only if database selected) ---
if [[ "$DB_TYPE" != "none" ]]; then
    echo "--- Database Configuration ---"
    
    # Determine database type label
    if [[ "$DB_TYPE" == "mysql" ]]; then
        DB_LABEL="MySQL"
        DEFAULT_DB_NAME="${APP_NAME}_db"
        DEFAULT_DB_USER="${APP_NAME}_user"
        DEFAULT_PORT=3306
    else
        DB_LABEL="PostgreSQL"
        DEFAULT_DB_NAME="${APP_NAME}_db"
        DEFAULT_DB_USER="${APP_NAME}_user"
        DEFAULT_PORT=5432
    fi
    
    # Database Name (common for all types)
    # ... existing database name prompt code ...
    
    # For PostgreSQL/PostGIS, different credential structure
    if [[ "$DB_TYPE" == "mysql" ]]; then
        # MySQL credentials (existing code)
        # ... user, password, root password prompts ...
    else
        # PostgreSQL credentials (simpler - no separate root user)
        # ... user and password prompts only ...
    fi
    
    # Port configuration
    DB_HOST_PORT=$(prompt_for_port "$DB_LABEL" $DEFAULT_PORT)
else
    # Set empty values when no database
    DB_DATABASE=""
    DB_USER=""
    DB_PASSWORD=""
    DB_ROOT_PASSWORD=""
    DB_HOST_PORT=""
fi
```

**Update setup2.sh call (line 538):**

```bash
# Pass DB_TYPE as 11th argument
./setup2.sh "$APP_NAME" "$DB_USER" "$DB_PASSWORD" "$DB_ROOT_PASSWORD" \
    "$DB_DATABASE" "$DB_HOST_PORT" "$MAILPIT_SMTP_PORT" "$MAILPIT_WEB_PORT" \
    "$ENABLE_MAILER" "$ENABLE_MERCURE" "$DB_TYPE"
```

#### B. [`setup/setup2.sh`](setup/setup2.sh:1) Changes

**Update argument count check (line 42):**

```bash
if [ "$#" -ne 11 ]; then
    echoc "31" "ERROR: This script must be called from setup.sh with 11 arguments."
    echoc "31" "Usage: ./setup2.sh <app_name> <db_user> <db_password> <db_root_password> <db_database> <db_host_port> <mailpit_smtp_port> <mailpit_web_port> <enable_mailer> <enable_mercure> <db_type>"
    exit 1
fi
```

**Add DB_TYPE variable (line 57):**

```bash
ENABLE_MERCURE=${10}
DB_TYPE=${11}
```

**Build Compose Files List (line 86):**

```bash
# --- 2. Build Compose Files List ---
COMPOSE_FILES="-f compose.yaml -f compose.override.yaml"

# Add database compose file based on selection
if [[ "$DB_TYPE" != "none" ]]; then
    COMPOSE_FILES="$COMPOSE_FILES -f compose.${DB_TYPE}.yaml"
fi

# Add optional features
if [[ "$ENABLE_MAILER" =~ ^[Yy]$ ]]; then
    COMPOSE_FILES="$COMPOSE_FILES -f compose.mailer.yaml"
fi

if [[ "$ENABLE_MERCURE" =~ ^[Yy]$ ]]; then
    COMPOSE_FILES="$COMPOSE_FILES -f compose.mercure.yaml"
fi
```

**Update .env file creation (line 108):**

```bash
cat > .env << EOF
# Docker Compose project name (automatic namespacing)
COMPOSE_PROJECT_NAME=${PROJECT_NAME}

# Database Type Selection
DB_TYPE=${DB_TYPE}

# Server Configuration
SERVER_NAME=localhost
HTTP_PORT=80
HTTPS_PORT=443
HTTP3_PORT=443
EOF

# Add database-specific configuration
if [[ "$DB_TYPE" == "mysql" ]]; then
    cat >> .env << EOF

# MySQL Database Configuration
MYSQL_VERSION=8
MYSQL_DATABASE=${DB_DATABASE}
MYSQL_USER=${DB_USER}
MYSQL_PASSWORD=${DB_PASSWORD}
MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
MYSQL_CHARSET=utf8mb4
DB_HOST_PORT=${DB_HOST_PORT}
EOF
elif [[ "$DB_TYPE" == "postgres" ]] || [[ "$DB_TYPE" == "postgis" ]]; then
    cat >> .env << EOF

# PostgreSQL Database Configuration
POSTGRES_DB=${DB_DATABASE}
POSTGRES_USER=${DB_USER}
POSTGRES_PASSWORD=${DB_PASSWORD}
DB_HOST_PORT=${DB_HOST_PORT}
EOF
fi

# Add Symfony configuration
cat >> .env << EOF

# Symfony Configuration
SYMFONY_VERSION=
STABILITY=stable

# Development Tools
XDEBUG_MODE=off
APP_ENV=dev
EOF
```

**Update database wait logic (line 259):**

```bash
# --- 7. Wait for Database (only if database is configured) ---
if [[ "$DB_TYPE" != "none" ]]; then
    echoc "36" "Waiting for database to be ready..."
    ATTEMPTS=90
    
    if [[ "$DB_TYPE" == "mysql" ]]; then
        until ${DOCKER_COMPOSE_CMD} ${COMPOSE_FILES} exec -T database mysqladmin ping -u${DB_USER} -p${DB_PASSWORD} --silent >/dev/null 2>&1 || [ $ATTEMPTS -eq 0 ]; do
            sleep 1
            ATTEMPTS=$((ATTEMPTS - 1))
            echo -n "."
        done
    else
        # PostgreSQL/PostGIS health check
        until ${DOCKER_COMPOSE_CMD} ${COMPOSE_FILES} exec -T database pg_isready -U ${DB_USER} >/dev/null 2>&1 || [ $ATTEMPTS -eq 0 ]; do
            sleep 1
            ATTEMPTS=$((ATTEMPTS - 1))
            echo -n "."
        done
    fi
    
    echo ""
    
    if [ $ATTEMPTS -eq 0 ]; then
        echoc "31" "ERROR: Database failed to become ready in time."
        exit 1
    fi
    
    echoc "32" "✔ Database is ready."
else
    echoc "36" "No database configured - skipping database checks."
fi
```

#### C. [`compose.yaml`](compose.yaml:1) Changes

**Remove duplicate database services:**

Remove lines 45-77 (both database service definitions). The [`compose.yaml`](compose.yaml:1) should NOT contain any database service - only the PHP service and volumes.

```yaml
services:
  php:
    image: app-php
    restart: unless-stopped
    environment:
      SERVER_NAME: ${SERVER_NAME:-localhost}, php:80
      DEFAULT_URI: https://${SERVER_NAME:-localhost}:${HTTPS_PORT:-443}
      # Database connection - will be overridden based on DB_TYPE
      # See compose.mysql.yaml, compose.postgres.yaml, or compose.postgis.yaml
      # Initial installation variables
      SYMFONY_VERSION: ${SYMFONY_VERSION:-}
      STABILITY: ${STABILITY:-stable}
    volumes:
      - caddy_data:/data
      - caddy_config:/config
    ports:
      - name: http
        target: 80
        published: ${HTTP_PORT:-80}
        protocol: tcp
      - name: https
        target: 443
        published: ${HTTPS_PORT:-443}
        protocol: tcp
      - name: http3
        target: 443
        published: ${HTTP3_PORT:-443}
        protocol: udp

volumes:
  caddy_data:
  caddy_config:
```

#### D. [`Makefile`](Makefile:1) Changes

**Add database compose file detection:**

```makefile
# Executables (local)
DOCKER_COMP = docker compose

# Detect which compose files to use based on .env configuration
# Read DB_TYPE from .env file (default to mysql if not set)
DB_TYPE := $(shell grep -E '^DB_TYPE=' .env 2>/dev/null | cut -d '=' -f2 || echo "mysql")

# Build compose file list
COMPOSE_FILES := -f compose.yaml -f compose.override.yaml

# Add database compose file if DB_TYPE is not "none"
ifneq ($(DB_TYPE),none)
    COMPOSE_FILES += -f compose.$(DB_TYPE).yaml
endif

# Add optional compose files if they should be included
# Check if mercure should be enabled by looking for CADDY_MERCURE_JWT_SECRET in .env
ifneq ($(shell grep -E '^CADDY_MERCURE_JWT_SECRET=' .env 2>/dev/null),)
    COMPOSE_FILES += -f compose.mercure.yaml
endif

# Check if mailer should be enabled
ifneq ($(shell grep -E '^MAILPIT_WEB_PORT=' .env 2>/dev/null),)
    COMPOSE_FILES += -f compose.mailer.yaml
endif

# Docker containers
PHP_CONT = $(DOCKER_COMP) $(COMPOSE_FILES) exec php

# Rest remains the same...
```

**Update make targets:**

```makefile
build: ## Builds the Docker images
	@$(DOCKER_COMP) $(COMPOSE_FILES) build --pull --no-cache

up: ## Start the docker hub in detached mode (no logs)
	@$(DOCKER_COMP) $(COMPOSE_FILES) up --detach

start: build up ## Build and start the containers

down: ## Stop the docker hub
	@$(DOCKER_COMP) $(COMPOSE_FILES) down --remove-orphans

logs: ## Show live logs
	@$(DOCKER_COMP) $(COMPOSE_FILES) logs --tail=0 --follow
```

#### E. [`.env.dev.example`](.env.dev.example:1) Changes

```env
# Copy this file to .env.dev.local and fill in the values.

###> symfony/framework-bundle ###
APP_ENV=dev
APP_SECRET=your-secret-key-here
###< symfony/framework-bundle ###

###> doctrine/doctrine-bundle ###
# Database Configuration
# The setup script will configure these based on your database selection.

# MySQL Configuration (if DB_TYPE=mysql)
MYSQL_USER=
MYSQL_PASSWORD=
MYSQL_DATABASE=
MYSQL_ROOT_PASSWORD=
MYSQL_VERSION=8
MYSQL_CHARSET=utf8mb4

# PostgreSQL Configuration (if DB_TYPE=postgres or DB_TYPE=postgis)
POSTGRES_DB=
POSTGRES_USER=
POSTGRES_PASSWORD=

# Database URL - will be set automatically based on DB_TYPE
# MySQL format:
# DATABASE_URL=mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@database:3306/${MYSQL_DATABASE}?serverVersion=${MYSQL_VERSION}&charset=${MYSQL_CHARSET}
#
# PostgreSQL format:
# DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@database:5432/${POSTGRES_DB}?serverVersion=18&charset=utf8
#
# PostGIS format:
# DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@database:5432/${POSTGRES_DB}?serverVersion=18&charset=utf8
DATABASE_URL=

###< doctrine/doctrine-bundle ###

###> symfony/mailer ###
# Use the "mailer" service name for Docker internal communication
# Or use host.docker.internal:1025 for shared Mailpit
MAILER_DSN=smtp://mailer:1025
###< symfony/mailer ###

###> symfony/mercure-bundle (OPTIONAL) ###
# MERCURE_URL=http://php/.well-known/mercure
# MERCURE_PUBLIC_URL=https://localhost/.well-known/mercure
# MERCURE_JWT_SECRET="!ChangeThisMercureHubJWTSecretKey!"
###< symfony/mercure-bundle ###
```

## Implementation Order

1. ✅ Fix [`compose.yaml`](compose.yaml:1) - Remove duplicate database services
2. ✅ Update [`.env.dev.example`](.env.dev.example:1) - Add support for all DB types
3. ✅ Update [`setup/setup.sh`](setup/setup.sh:1) - Add database selection prompts
4. ✅ Update [`setup/setup2.sh`](setup/setup2.sh:1) - Handle DB_TYPE and conditional logic
5. ✅ Update [`Makefile`](Makefile:1) - Dynamic compose file inclusion
6. ✅ Update [`compose.yaml`](compose.yaml:1) php service - Remove hardcoded DATABASE_URL
7. ✅ Test all database options

## Testing Strategy

### Test Cases
1. **No Database:** Select "no database" - verify no db service starts
2. **MySQL:** Full MySQL setup with custom credentials and ports
3. **PostgreSQL:** PostgreSQL setup with custom credentials and ports  
4. **PostGIS:** PostGIS setup with custom credentials and ports
5. **Mercure + Database:** Verify both features work together
6. **Mailer + Database:** Verify both features work together

### Verification Commands
```bash
# Check which compose files are being used
make -n up

# Verify .env contains correct DB_TYPE
cat .env | grep DB_TYPE

# Check running containers
docker ps

# Verify database connection
docker compose exec php php bin/console dbal:run-sql "SELECT 1"
```

## Benefits

1. **Clean Architecture:** No database services in base [`compose.yaml`](compose.yaml:1)
2. **Flexibility:** Users can choose database or run without one
3. **Consistency:** Follows existing Mercure pattern
4. **Maintainability:** Each database type in its own compose file
5. **No Breaking Changes:** Existing projects continue working with MySQL default

## Migration Notes

For existing projects that expect MySQL in [`compose.yaml`](compose.yaml:1):
- Add `DB_TYPE=mysql` to their `.env` file
- The Makefile will automatically include `compose.mysql.yaml`
- No other changes needed