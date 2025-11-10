#!/bin/bash
#
# Symfony Docker Environment Setup Script - PART 2
#
# This script is executed from within the new project directory.
# It receives user input as arguments and performs the main configuration and installation.
# NEW: Includes a 'trap' to clean up Docker services on any failure.

set -e # Exit immediately if a command exits with a non-zero status

# --- Helper function for colored output (copied from setup.sh) ---
echoc() {
    COLOR=$1
    shift
    echo -e "\033[${COLOR}m$@\033[0m"
}

# --- Cleanup function to run on failure ---
# This trap will catch any command failure (due to set -e)
cleanup_on_error() {
    # $? is the exit code of the failed command
    local exit_code=$?
    echoc "31" "============================================================"
    echoc "31" "ERROR: A command failed with exit code $exit_code."
    echoc "31" "Rollback: Attempting to clean up Docker services..."
    
    # Try to run docker compose down to remove containers and volumes
    if [ -n "$DOCKER_COMPOSE_CMD" ]; then
        ${DOCKER_COMPOSE_CMD} down --volumes --remove-orphans >/dev/null 2>&1
        echoc "31" "Rollback: Docker services for this project have been stopped and removed."
    else
        echoc "33" "Rollback: DOCKER_COMPOSE_CMD not set, cannot clean up services."
    fi
    
    echoc "31" "Exiting setup. The project directory will be removed by setup.sh."
    echoc "31" "============================================================"
    exit $exit_code
}

# Set the trap to call cleanup_on_error on any ERR signal (command failure)
trap cleanup_on_error ERR

# --- 1. Receive User Input from Arguments (8 ARGUMENTS EXPECTED) ---
if [ "$#" -ne 8 ]; then
    echoc "31" "ERROR: This script must be called from setup.sh with 8 arguments."
    echoc "31" "Usage: ./setup2.sh <app_container_name> <db_user> <db_password> <db_root_password> <db_database> <db_host_port> <mailpit_smtp_port> <mailpit_web_port>"
    exit 1
fi

APP_CONTAINER_NAME=$1
DB_USER=$2
DB_PASSWORD=$3
DB_ROOT_PASSWORD=$4
DB_DATABASE=$5
DB_HOST_PORT=$6
MAILPIT_SMTP_PORT=$7
MAILPIT_WEB_PORT=$8

# Define PHP Container Name (used for exec commands)
PHP_CONTAINER_NAME="${APP_CONTAINER_NAME}-php"
# Enforce lowercase for dependency targeting and volume naming for better compatibility
LOWER_APP_CONTAINER_NAME=$(echo "$APP_CONTAINER_NAME" | tr '[:upper:]' '[:lower:]')

echoc "33" "--- Setup Part 2 Initializing ---"
echoc "36" "Container Name: ${APP_CONTAINER_NAME}"
echoc "36" "Database Name:  ${DB_DATABASE}"
echoc "36" "DB Host Port:   ${DB_HOST_PORT}"
echoc "36" "Mailer Web Port: ${MAILPIT_WEB_PORT}"
echoc "36" "Mailer SMTP Port: ${MAILPIT_SMTP_PORT}"
echo ""

# Define DOCKER_COMPOSE_CMD *early* so the trap function can use it.
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echoc "31" "ERROR: Docker Compose command not found. Cannot proceed with setup."
    exit 1
fi

# --- 2. Configure Environment Variables ---
echo "--- Configuring Environment Variables ---"

# 2a. Create .env.dev.local from the example file
cp .env.dev.example .env.dev.local
echo "Creating .env.dev.local..."

# 2b. Use sed to replace the placeholders in .env.dev.local
sed -i "
    s#^MYSQL_USER=.*#MYSQL_USER=${DB_USER}#;
    s#^MYSQL_PASSWORD=.*#MYSQL_PASSWORD=${DB_PASSWORD}#;
    s#^MYSQL_ROOT_PASSWORD=.*#MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}#;
    s#^MYSQL_DATABASE=.*#MYSQL_DATABASE=${DB_DATABASE}#;
" .env.dev.local

# 2c. Update the host port in the DATABASE_URL line
sed -i "s#:3306/#:${DB_HOST_PORT}/#g" .env.dev.local

echoc "32" "✔ .env.dev.local created and configured."
echo ""

# --- IMPORTANT: Export variables to the shell for Docker Compose ---
export MYSQL_USER="${DB_USER}"
export MYSQL_PASSWORD="${DB_PASSWORD}"
export MYSQL_ROOT_PASSWORD="${DB_ROOT_PASSWORD}"
export MYSQL_DATABASE="${DB_DATABASE}"
export DB_HOST_PORT="${DB_HOST_PORT}"

# --- 3. Preparing Docker Configuration ---
echo "--- Preparing Docker Configuration ---"

# 3a. Define the correct file names
COMPOSE_FILE="compose.yaml" 
COMPOSE_OVERRIDE_FILE="compose.override.yaml" 

# 3b. Update container names, ports, and volumes in compose.yaml
sed -i "
    # [FIX 1: ENTRYPOINT ERROR] CRITICAL: Remove explicit 'command' or 'entrypoint' from the PHP service.
    /^\s\scommand:.*$/d;
    /^\s\sentrypoint:.*$/d;

    # [FIX 2: NAMING & DEPENDENCY] Rename container and ensure correct dependencies:
    s#^  container_name: php-app.*#  container_name: ${APP_CONTAINER_NAME}-php#;
    s#^      - ${APP_CONTAINER_NAME}-database#      - database#;

    # Rename the container_name for database and update port
    s#^  container_name: database-app.*#  container_name: ${APP_CONTAINER_NAME}-database#;
    s#^    ports:.*#    ports:#;
    s#^      - \"3306:3306\".*#      - \"${DB_HOST_PORT}:3306\"#;
    
    # [FIX 3: VOLUME DUPLICATION] Update volume placeholder name to stop double prefixing.
    s#machinistmate_volume:#db_data:#g;
    s#machinistmate_volume:/var/lib/mysql#db_data:/var/lib/mysql#g;
" "${COMPOSE_FILE}"

# 3c. Update Mailpit ports in compose.override.yaml
sed -i "
    # Replace the unmapped 1025 port with the user-defined host port 
    s/^      - \"1025\"/      - \"${MAILPIT_SMTP_PORT}:1025\"/;

    # Replace the unmapped 8025 port with the user-defined host port 
    s/^      - \"8025\"/      - \"${MAILPIT_WEB_PORT}:8025\"/;
    
    # Ensure the PHP service in the override file depends on the generic database service key 'database'.
    s#^      - ${APP_CONTAINER_NAME}-database#      - database#
" "${COMPOSE_OVERRIDE_FILE}"


echoc "32" "✔ Docker configuration updated."
echo ""

# --- 4. Building Docker Images (this may take a few minutes) ---
echo "--- Building Docker Images (this may take a few minutes) ---"
${DOCKER_COMPOSE_CMD} build --pull --no-cache
echoc "32" "✔ Docker images built."
echo ""

# --- 5. Start Services ---
echo "--- Starting Docker Containers ---"
${DOCKER_COMPOSE_CMD} up -d
echoc "32" "✔ Containers started. Waiting for database to become available..."

# Wait for database service to be healthy
echoc "36" "Waiting for database service 'database' to be healthy..."
# CRITICAL FIX: Use --entrypoint /bin/sh to bypass the base image's entrypoint when running single commands 
${DOCKER_COMPOSE_CMD} run --rm --no-deps --entrypoint /bin/sh -e SKIP_DB_WAIT=1 php -c "php /usr/local/bin/docker-wait-for-database database"

echoc "32" "✔ All services are up and running."
echo ""

# --- 6. Install Dependencies ---
echo "--- Installing Project Dependencies ---"

# Install PHP dependencies
echoc "36" "Running 'composer install' in container '${APP_CONTAINER_NAME}-php' (Service: php)..."
${DOCKER_COMPOSE_CMD} exec -T php composer install --no-interaction --prefer-dist --optimize-autoloader

# Install Node.js dependencies
echoc "36" "Running 'yarn install' in container '${APP_CONTAINER_NAME}-php' (Service: php)..."
${DOCKER_COMPOSE_CMD} exec -T php yarn install

echoc "32" "✔ Dependencies installed."
echo ""

# --- 7. Setup Database and Assets ---
echo "--- Finalizing Application Setup ---"

# Run database migrations
echoc "36" "Running database migrations (if any)..."
${DOCKER_COMPOSE_CMD} exec -T php php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration

# Build frontend assets
echoc "36" "Building frontend assets..."
${DOCKER_COMPOSE_CMD} exec -T php yarn build

echo ""
echoc "32" "=============================================================="
echoc "32" "✅  SUCCESS: Your development environment is ready!"
echoc "32" "=============================================================="
echo ""
echo "  Project Root:     ./${APP_CONTAINER_NAME}"
echo "  Application URL:  https://localhost (or http://localhost:8080)"
echo "  Mailpit (Email):  http://localhost:${MAILPIT_WEB_PORT}"
echo ""
echo "  To stop the project, run: docker compose down"
echo "  To restart the project, run: docker compose up -d"
echo "  To run a PHP command, use: docker compose exec ${APP_CONTAINER_NAME}-php php ..."
echo ""

# Explicitly exit with 0 on success to signal to setup.sh that all is well
exit 0