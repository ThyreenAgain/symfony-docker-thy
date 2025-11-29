#!/bin/bash
#
# Symfony Docker Environment Setup Script - PART 2
#
# This script is executed from within the new project directory.
# It receives user input as arguments and performs the main configuration and installation.
# Uses COMPOSE_PROJECT_NAME for automatic resource namespacing (Docker best practice).
# Supports modular optional features via separate compose files.

set -e # Exit immediately if a command exits with a non-zero status

# --- Helper function for colored output ---
echoc() {
    COLOR=$1
    shift
    echo -e "\033[${COLOR}m$@\033[0m"
}

# --- Cleanup function to run on failure ---
cleanup_on_error() {
    local exit_code=$?
    exit $exit_code
    echoc "31" "============================================================"
    echoc "31" "ERROR: A command failed with exit code $exit_code."
    echoc "31" "Rollback: Attempting to clean up Docker services..."
    
    if [ -n "$DOCKER_COMPOSE_CMD" ] && [ -n "$COMPOSE_FILES" ]; then
        ${DOCKER_COMPOSE_CMD} ${COMPOSE_FILES} down --volumes --remove-orphans >/dev/null 2>&1
        echoc "31" "Rollback: Docker services have been stopped and removed."
    else
        echoc "33" "Rollback: DOCKER_COMPOSE_CMD not set, cannot clean up services."
    fi
    
    echoc "31" "Exiting setup. The project directory will be removed by setup.sh."
    echoc "31" "============================================================"
    exit $exit_code
}

# Set the trap to call cleanup_on_error on any ERR signal
trap cleanup_on_error ERR

# --- 1. Receive User Input from Arguments (11 ARGUMENTS EXPECTED) ---
if [ "$#" -ne 11 ]; then
    echoc "31" "ERROR: This script must be called from setup.sh with 11 arguments."
    echoc "31" "Usage: ./setup2.sh <app_name> <db_user> <db_password> <db_root_password> <db_database> <db_host_port> <mailpit_smtp_port> <mailpit_web_port> <enable_mailer> <enable_mercure> <db_type>"
    exit 1
fi

APP_NAME=$1
DB_USER=$2
DB_PASSWORD=$3
DB_ROOT_PASSWORD=$4
DB_DATABASE=$5
DB_HOST_PORT=$6
MAILPIT_SMTP_PORT=$7
MAILPIT_WEB_PORT=$8
ENABLE_MAILER=$9
ENABLE_MERCURE=${10}
DB_TYPE=${11}

# Convert app name to lowercase for Docker Compose project name
PROJECT_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

echoc "33" "--- Setup Part 2 Initializing ---"
echoc "36" "Project Name:     ${APP_NAME}"
echoc "36" "Compose Project:  ${PROJECT_NAME}"
echoc "36" "Database Type:    ${DB_TYPE}"
if [[ "$DB_TYPE" != "none" ]]; then
    echoc "36" "Database Name:    ${DB_DATABASE}"
    echoc "36" "DB Host Port:     ${DB_HOST_PORT}"
fi
if [[ "$ENABLE_MAILER" =~ ^[Yy]$ ]]; then
    echoc "36" "Mailpit Web:      ${MAILPIT_WEB_PORT}"
    echoc "36" "Mailpit SMTP:     ${MAILPIT_SMTP_PORT}"
fi
echoc "36" "Mailer Enabled:   ${ENABLE_MAILER}"
echoc "36" "Mercure Enabled:  ${ENABLE_MERCURE}"
echo ""

# Define DOCKER_COMPOSE_CMD early so the trap function can use it
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echoc "31" "ERROR: Docker Compose command not found. Cannot proceed with setup."
    exit 1
fi

# --- 2. Build Compose Files List ---
COMPOSE_FILES="-f compose.yaml -f compose.override.yaml"

# Add database compose file based on selection
if [[ "$DB_TYPE" != "none" ]]; then
    COMPOSE_FILES="$COMPOSE_FILES -f compose.${DB_TYPE}.yaml"
fi

if [[ "$ENABLE_MAILER" =~ ^[Yy]$ ]]; then
    COMPOSE_FILES="$COMPOSE_FILES -f compose.mailer.yaml"
fi

if [[ "$ENABLE_MERCURE" =~ ^[Yy]$ ]]; then
    COMPOSE_FILES="$COMPOSE_FILES -f compose.mercure.yaml"
fi

echoc "32" "✔ Using compose files: ${COMPOSE_FILES}"
echo ""

# --- 3. Set Docker Compose Project Name ---
export COMPOSE_PROJECT_NAME="${PROJECT_NAME}"
echoc "32" "✔ Docker Compose project name set to: ${COMPOSE_PROJECT_NAME}"
echo ""

# --- 4. Configure Environment Variables ---
echo "--- Configuring Environment Variables ---"

# Create .env file for Docker Compose
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
SYMFONY_VERSION=${SYMFONY_VERSION}
STABILITY=${STABILITY}

# Development Tools
XDEBUG_MODE=off
APP_ENV=dev
EOF

# Add Mailpit configuration if project-specific Mailpit is enabled
if [[ "$ENABLE_MAILER" == "y" ]] && [[ -n "$MAILPIT_SMTP_PORT" ]] && [[ -n "$MAILPIT_WEB_PORT" ]]; then
    cat >> .env << EOF

# Mailpit Configuration (Email Testing - Project-Specific)
MAILPIT_SMTP_PORT=${MAILPIT_SMTP_PORT}
MAILPIT_WEB_PORT=${MAILPIT_WEB_PORT}
EOF
fi

# Add Mercure configuration if enabled
if [[ "$ENABLE_MERCURE" =~ ^[Yy]$ ]]; then
    cat >> .env << EOF

# Mercure Hub Configuration (Real-Time Messaging)
CADDY_MERCURE_JWT_SECRET=!ChangeThisMercureHubJWTSecretKey!
CADDY_MERCURE_URL=http://php/.well-known/mercure
CADDY_MERCURE_PUBLIC_URL=https://localhost:443/.well-known/mercure
EOF
fi

echoc "32" "✔ .env file created with project configuration."

# Update parent .env file for DB_TYPE and remove unused DB vars
if [ -f "../.env" ]; then
    cp ../.env ../.env.bak
    sed -i '/MYSQL_USER=/d;/MYSQL_PASSWORD=/d;/MYSQL_DATABASE=/d;/MYSQL_ROOT_PASSWORD=/d;/MYSQL_VERSION=/d;/MYSQL_CHARSET=/d;/POSTGRES_DB=/d;/POSTGRES_USER=/d;/POSTGRES_PASSWORD=/d;/DB_TYPE=/d' ../.env
    echo "DB_TYPE=${DB_TYPE}" >> ../.env
    if [[ "$DB_TYPE" == "mysql" ]]; then
        echo "MYSQL_USER=${DB_USER}" >> ../.env
        echo "MYSQL_PASSWORD=${DB_PASSWORD}" >> ../.env
        echo "MYSQL_DATABASE=${DB_DATABASE}" >> ../.env
        echo "MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}" >> ../.env
        echo "MYSQL_VERSION=8" >> ../.env
        echo "MYSQL_CHARSET=utf8mb4" >> ../.env
    elif [[ "$DB_TYPE" == "postgres" || "$DB_TYPE" == "postgis" ]]; then
        echo "POSTGRES_DB=${DB_DATABASE}" >> ../.env
        echo "POSTGRES_USER=${DB_USER}" >> ../.env
        echo "POSTGRES_PASSWORD=${DB_PASSWORD}" >> ../.env
    fi
fi

# Update parent .env.dev.local for DB_TYPE and user values
if [ -f "../.env.dev.local" ]; then
    cp ../.env.dev.local ../.env.dev.local.bak
    sed -i '/MYSQL_USER=/d;/MYSQL_PASSWORD=/d;/MYSQL_DATABASE=/d;/MYSQL_ROOT_PASSWORD=/d;/MYSQL_VERSION=/d;/MYSQL_CHARSET=/d;/POSTGRES_DB=/d;/POSTGRES_USER=/d;/POSTGRES_PASSWORD=/d;/DB_TYPE=/d' ../.env.dev.local
    echo "DB_TYPE=${DB_TYPE}" >> ../.env.dev.local
    if [[ "$DB_TYPE" == "mysql" ]]; then
        echo "MYSQL_USER=${DB_USER}" >> ../.env.dev.local
        echo "MYSQL_PASSWORD=${DB_PASSWORD}" >> ../.env.dev.local
        echo "MYSQL_DATABASE=${DB_DATABASE}" >> ../.env.dev.local
        echo "MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}" >> ../.env.dev.local
        echo "MYSQL_VERSION=8" >> ../.env.dev.local
        echo "MYSQL_CHARSET=utf8mb4" >> ../.env.dev.local
    elif [[ "$DB_TYPE" == "postgres" || "$DB_TYPE" == "postgis" ]]; then
        echo "POSTGRES_DB=${DB_DATABASE}" >> ../.env.dev.local
        echo "POSTGRES_USER=${DB_USER}" >> ../.env.dev.local
        echo "POSTGRES_PASSWORD=${DB_PASSWORD}" >> ../.env.dev.local
    fi
fi

# Create .env.dev.local from the example file
if [ -f .env.dev.example ]; then
    cp .env.dev.example .env.dev.local
    echoc "36" "Creating .env.dev.local..."
    
    # Update database credentials based on DB_TYPE
    if [[ "$DB_TYPE" != "none" ]]; then
        echoc "36" "Updating database credentials for ${DB_TYPE}..."
        
        if [[ "$DB_TYPE" == "mysql" ]]; then
            # MySQL configuration
            sed -i \
                -e "s|^MYSQL_USER=.*|MYSQL_USER=${DB_USER}|" \
                -e "s|^MYSQL_PASSWORD=.*|MYSQL_PASSWORD=${DB_PASSWORD}|" \
                -e "s|^MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}|" \
                -e "s|^MYSQL_DATABASE=.*|MYSQL_DATABASE=${DB_DATABASE}|" \
                .env.dev.local
            
            # Set DATABASE_URL for MySQL
            echo "" >> .env.dev.local
            echo "# Database URL (MySQL)" >> .env.dev.local
            echo "DATABASE_URL=mysql://\${MYSQL_USER}:\${MYSQL_PASSWORD}@database:3306/\${MYSQL_DATABASE}?serverVersion=\${MYSQL_VERSION}&charset=\${MYSQL_CHARSET}" >> .env.dev.local
        else
            # PostgreSQL/PostGIS configuration
            sed -i \
                -e "s|^POSTGRES_DB=.*|POSTGRES_DB=${DB_DATABASE}|" \
                -e "s|^POSTGRES_USER=.*|POSTGRES_USER=${DB_USER}|" \
                -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${DB_PASSWORD}|" \
                .env.dev.local
            
            # Set DATABASE_URL for PostgreSQL/PostGIS
            echo "" >> .env.dev.local
            echo "# Database URL (PostgreSQL/PostGIS)" >> .env.dev.local
            echo "DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@database:5432/\${POSTGRES_DB}?serverVersion=18&charset=utf8" >> .env.dev.local
        fi
    fi
    
    # Configure Mailer DSN for shared Mailpit if not using project-specific Mailpit
    if [[ ! "$ENABLE_MAILER" =~ ^[Yy]$ ]]; then
        echoc "36" "Configuring to use shared Mailpit instance..."
        # Add or update MAILER_DSN to use host.docker.internal
        if grep -q "^MAILER_DSN=" .env.dev.local 2>/dev/null; then
            sed -i "s|^MAILER_DSN=.*|MAILER_DSN=smtp://host.docker.internal:1025|" .env.dev.local
        else
            echo "" >> .env.dev.local
            echo "# Mailer configuration (using shared Mailpit)" >> .env.dev.local
            echo "MAILER_DSN=smtp://host.docker.internal:1025" >> .env.dev.local
        fi
        echoc "32" "✔ Configured to use shared Mailpit at host.docker.internal:1025"
    fi
    
    # Uncomment Mercure configuration if enabled
    if [[ "$ENABLE_MERCURE" =~ ^[Yy]$ ]]; then
        sed -i \
            -e "s|^# MERCURE_URL=|MERCURE_URL=|" \
            -e "s|^# MERCURE_PUBLIC_URL=|MERCURE_PUBLIC_URL=|" \
            -e "s|^# MERCURE_JWT_SECRET=|MERCURE_JWT_SECRET=|" \
            .env.dev.local
    fi
    
    echoc "32" "✔ .env.dev.local created and configured."
fi

# Create .dockerignore if using optional features (helps with build context)
cat > .dockercompose << EOF
# Docker Compose configuration
# This file specifies which compose files to use

version: '3'
files:
  - compose.yaml
  - compose.override.yaml
EOF

if [[ "$ENABLE_MAILER" =~ ^[Yy]$ ]]; then
    echo "  - compose.mailer.yaml" >> .dockercompose
fi

if [[ "$ENABLE_MERCURE" =~ ^[Yy]$ ]]; then
    echo "  - compose.mercure.yaml" >> .dockercompose
fi

echoc "32" "✔ .dockercompose file created for easy reference."

    # Enable Mercure in Caddyfile if requested
    if [[ "$ENABLE_MERCURE" =~ ^[Yy]$ ]]; then
        echoc "36" "Enabling Mercure in Caddyfile..."
        # Uncomment the Mercure section in the Caddyfile
        sed -i \
            -e "s|^# \+mercure {|mercure {|" \
            -e "s|^# \+# Publisher JWT key|# Publisher JWT key|" \
            -e "s|^# \+publisher_jwt {env.MERCURE_PUBLISHER_JWT_KEY} {env.MERCURE_PUBLISHER_JWT_ALG}|publisher_jwt {env.MERCURE_PUBLISHER_JWT_KEY} {env.MERCURE_PUBLISHER_JWT_ALG}|" \
            -e "s|^# \+# Subscriber JWT key|# Subscriber JWT key|" \
            -e "s|^# \+subscriber_jwt {env.MERCURE_SUBSCRIBER_JWT_KEY} {env.MERCURE_SUBSCRIBER_JWT_ALG}|subscriber_jwt {env.MERCURE_SUBSCRIBER_JWT_KEY} {env.MERCURE_SUBSCRIBER_JWT_ALG}|" \
            -e "s|^# \+# Allow anonymous subscribers (double-check that it's what you want)|# Allow anonymous subscribers (double-check that it's what you want)|" \
            -e "s|^# \+anonymous|anonymous|" \
            -e "s|^# \+# Enable the subscription API (double-check that it's what you want)|# Enable the subscription API (double-check that it's what you want)|" \
            -e "s|^# \+subscriptions|subscriptions|" \
            -e "s|^# \+# Extra directives|# Extra directives|" \
            -e "s|^# \+{$MERCURE_EXTRA_DIRECTIVES}|{$MERCURE_EXTRA_DIRECTIVES}|" \
            -e "s|^# \+}|}|" \
            frankenphp/Caddyfile
        echoc "32" "✔ Mercure enabled in Caddyfile."
    fi

echo ""

# --- 5. Building Docker Images ---
echo "--- Building Docker Images (this may take a few minutes) ---"
${DOCKER_COMPOSE_CMD} ${COMPOSE_FILES} build --pull --no-cache
echoc "32" "✔ Docker images built."
echo ""

# --- 6. Start Services ---
echo "--- Starting Docker Containers ---"
${DOCKER_COMPOSE_CMD} ${COMPOSE_FILES} up -d
echoc "32" "✔ Containers started."
echo ""

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
echo ""


echo ""

# --- 8. Database Migrations (if applicable) ---
if [ -f composer.json ] && grep -q "doctrine/doctrine-bundle" composer.json 2>/dev/null; then
    echo "--- Running Database Migrations ---"
    echoc "36" "Running database migrations (if any)..."
    ${DOCKER_COMPOSE_CMD} ${COMPOSE_FILES} exec -T php php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration || true
    
    if [ -f package.json ] && grep -q "@symfony/webpack-encore" package.json 2>/dev/null; then
        echoc "36" "Building frontend assets..."
        ${DOCKER_COMPOSE_CMD} ${COMPOSE_FILES} exec -T php yarn build || true
    fi
fi
 
# --- 9. Clean Up Installer Files ---
echo --- Cleaning up installer files ---
# Remove installer-specific files (not needed in user project)
rm -f install.sh DATABASE_SELECTION_IMPLEMENTATION_SUMMARY.md ARCHITECTURE_PLAN_DB_SELECTION.md README.md TODO_AUTOMATED_TESTS.md KNOWN_ISSUES.md UPGRADE_NOTES.md OPTIONAL_FEATURES.md 2>/dev/null  || true

# Remove installer directories
if [ -d "setup" ]; then rm -rf setup 2>/dev/null  || true;; fi
if [ -d "docs" ]; then rm -rf docs 2>/dev/null  || true;; fi

# Create clean project info
cat > PROJECT_INFO.md << "EOF"
# Project Created with Symfony Docker Template

This project was created using the Symfony Docker Template.
For complete documentation, visit: https://github.com/ThyreenAgain/symfony-docker-thy

## Quick Start
make up    # Start services
make help  # Show all commands
EOF
echoc "32" "✔ Installer files cleaned up."
echo ""

# --- 11. Success Message ---

# --- 10. Success Message ---
echo ""
echoc "32" "=============================================================="
echoc "32" "✅  SUCCESS: Your development environment is ready!"
echoc "32" "=============================================================="
echo ""
echo "  Project Name:     ${APP_NAME}"
echo "  Project Root:     $(pwd)"
echo "  Application URL:  https://localhost"
if [[ "$ENABLE_MAILER" == "y" ]] && [[ -n "$MAILPIT_WEB_PORT" ]]; then
    echo "  Mailpit (Email):  http://localhost:${MAILPIT_WEB_PORT}"
elif [[ "$ENABLE_MAILER" == "n" ]]; then
    echo "  Mailpit (Email):  http://localhost:8025 (shared)"
fi
if [[ "$DB_TYPE" != "none" ]] && [[ -n "$DB_HOST_PORT" ]]; then
    echo "  Database Port:    localhost:${DB_HOST_PORT}"
fi
echo ""
echo "Enabled Features:"
if [[ "$ENABLE_MAILER" == "y" ]] && [[ -n "$MAILPIT_WEB_PORT" ]]; then
    echo "  ✓ Mailpit (Email testing - project-specific)"
elif [[ "$ENABLE_MAILER" == "n" ]] && [[ -z "$MAILPIT_WEB_PORT" ]]; then
    echo "  ✓ Mailpit (Email testing - using shared instance at localhost:8025)"
fi
if [[ "$ENABLE_MERCURE" =~ ^[Yy]$ ]]; then
    echo "  ✓ Mercure Hub (Real-time messaging)"
fi
echo ""
echo "To start/stop services, use these commands:"
echo "  docker compose ${COMPOSE_FILES} up -d"
echo "  docker compose ${COMPOSE_FILES} down"
echo ""
echo "Or use the Makefile shortcuts:"
echo "  make up    # Start services"
echo "  make down  # Stop services"
echo "  make logs  # View logs"
echo "  make help  # See all commands"
echo ""
echoc "32" "All resources are namespaced with '${PROJECT_NAME}-' prefix."
echo ""

# Explicitly exit with 0 on success
exit 0
