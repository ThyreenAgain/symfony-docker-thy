#!/bin/bash
#
# Symfony Docker Environment Setup Script
#
# This script performs the following actions:
# 1. Checks for Docker, Docker Compose, and Git.
# 2. Prompts the user for project name, database credentials, and unique ports.
# 3. Asks about optional features (Mercure, Mailer).
# 4. Clones the symfony-docker template repository.
# 5. Calls setup2.sh to configure and install the environment.
# 6. Uses COMPOSE_PROJECT_NAME for automatic Docker resource namespacing.

set -e # Exit immediately if a command exits with a non-zero status

# --- Helper function for colored output ---
echoc() {
    COLOR=$1
    shift
    echo -e "\033[${COLOR}m$@\033[0m"
}

# --- Determine the correct user for file ownership ---
if [ -n "$SUDO_USER" ]; then
    CURRENT_USER=$SUDO_USER
else
    CURRENT_USER=$(whoami)
fi
echoc "36" "Running setup as user: $CURRENT_USER"
echo ""

# --- 1. Dependency Checks ---
echo "--- Checking dependencies ---"
if ! command -v docker &> /dev/null; then
    echoc "31" "ERROR: 'docker' command not found. Please install it."
    exit 1
fi

# Check for 'docker compose' (v2) first, then fallback to 'docker-compose' (v1)
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echoc "31" "ERROR: Docker Compose command not found. Please install Docker Desktop (which includes Docker Compose v2) or docker-compose (v1)."
    exit 1
fi

# Check for Git
if ! command -v git &> /dev/null; then
    echoc "31" "ERROR: 'git' command not found. Please install it to proceed with project setup."
    exit 1
fi

echoc "32" "✔ Docker, Docker Compose, and Git found."
echo ""

# --- 2. User Input ---
echo "--- Gathering Project Details ---"
echo ""
echoc "36" "Project Naming:"
echoc "36" "  The project name will be used for Docker Compose project namespacing."
echoc "36" "  All containers, volumes, and networks will be prefixed automatically."
echoc "36" "  Example: 'invoice_app' becomes 'invoice-app-php-1', 'invoice-app_db_data', etc."
echo ""

# --- Get Project Name ---
read -p "Enter a unique project name (e.g., 'invoice_app'): " APP_NAME

if [ -z "$APP_NAME" ]; then
    echoc "31" "Project name cannot be empty."
    exit 1
fi

# --- Set Custom Git Repository URL (Hardcoded) ---
GIT_REPO_URL="https://github.com/ThyreenAgain/symfony-docker-thy"
echoc "36" "Using template repository: $GIT_REPO_URL"
echo ""

# --- Optional Features ---
echo "--- Optional Features ---"
echoc "36" "The following features can be added to your project:"
echo ""

# Ask about Mailer
echoc "36" "📧 Mailer (Mailpit):"
echoc "36" "   Email testing service with web UI to catch and inspect emails."
echoc "36" "   Useful for testing email functionality in development."
read -p "   Enable Mailer/Mailpit? (y/n, default: y): " ENABLE_MAILER
ENABLE_MAILER=${ENABLE_MAILER:-y}
echo ""

# Ask about Mercure
echoc "36" "⚡ Mercure Hub:"
echoc "36" "   Real-time messaging for live updates (Server-Sent Events)."
echoc "36" "   Only needed if you're building apps with real-time features."
read -p "   Enable Mercure? (y/n, default: n): " ENABLE_MERCURE
ENABLE_MERCURE=${ENABLE_MERCURE:-n}
echo ""

# --- Get DB Credentials ---
echo "--- Database Configuration ---"
read -p "Enter MySQL Database Name (Default: '${APP_NAME}_db'): " DB_DATABASE
DB_DATABASE=${DB_DATABASE:-"${APP_NAME}_db"}

# Set default MySQL User based on the project name (lowercase)
DEFAULT_DB_USER=$(echo "${APP_NAME}_user" | tr '[:upper:]' '[:lower:]')
read -p "Enter MySQL User (Default: '${DEFAULT_DB_USER}'): " DB_USER
DB_USER=${DB_USER:-"${DEFAULT_DB_USER}"}

read -s -p "Enter MySQL Password: " DB_PASSWORD
echo ""
if [ -z "$DB_PASSWORD" ]; then
    echoc "31" "Database password cannot be empty."
    exit 1
fi

read -s -p "Enter MySQL Root Password: " DB_ROOT_PASSWORD
echo ""
if [ -z "$DB_ROOT_PASSWORD" ]; then
    echoc "31" "Database root password cannot be empty."
    exit 1
fi

echo ""
echoc "36" "--- Port Configuration ---"
echoc "36" "Standard ports: HTTP=80, HTTPS=443, MySQL=3306"
if [[ "$ENABLE_MAILER" =~ ^[Yy]$ ]]; then
    echoc "36" "                Mailpit SMTP=1025, Mailpit Web=8025"
fi
echoc "36" "Change these ONLY if you run multiple projects simultaneously."
echo ""

# --- Get Unique Ports ---
read -p "Enter Host Port for MySQL (Default: 3306): " DB_HOST_PORT
DB_HOST_PORT=${DB_HOST_PORT:-3306}

if ! [[ "$DB_HOST_PORT" =~ ^[0-9]+$ ]] || [ "$DB_HOST_PORT" -lt 1024 ] || [ "$DB_HOST_PORT" -gt 65535 ]; then
    echoc "31" "Invalid port number. Must be between 1024 and 65535."
    exit 1
fi

# Only ask for Mailpit ports if enabled
if [[ "$ENABLE_MAILER" =~ ^[Yy]$ ]]; then
    read -p "Enter Host Port for Mailpit SMTP (Default: 1025): " MAILPIT_SMTP_PORT
    MAILPIT_SMTP_PORT=${MAILPIT_SMTP_PORT:-1025}
    
    if ! [[ "$MAILPIT_SMTP_PORT" =~ ^[0-9]+$ ]] || [ "$MAILPIT_SMTP_PORT" -lt 1024 ] || [ "$MAILPIT_SMTP_PORT" -gt 65535 ]; then
        echoc "31" "Invalid port number."
        exit 1
    fi
    
    read -p "Enter Host Port for Mailpit Web UI (Default: 8025): " MAILPIT_WEB_PORT
    MAILPIT_WEB_PORT=${MAILPIT_WEB_PORT:-8025}
    
    if ! [[ "$MAILPIT_WEB_PORT" =~ ^[0-9]+$ ]] || [ "$MAILPIT_WEB_PORT" -lt 1024 ] || [ "$MAILPIT_WEB_PORT" -gt 65535 ]; then
        echoc "31" "Invalid port number."
        exit 1
    fi
else
    MAILPIT_SMTP_PORT=1025
    MAILPIT_WEB_PORT=8025
fi

echo ""
echoc "32" "All configuration gathered. Starting setup..."
echo ""

# --- 3. Create Project Directory ---
if [ -d "$APP_NAME" ]; then
    echoc "31" "ERROR: Directory '${APP_NAME}' already exists. Please choose a different project name."
    exit 1
fi

echo "--- Cloning Symfony Docker Template ---"
echoc "36" "Cloning repository: $GIT_REPO_URL"

# Clone to temporary directory
git clone --depth 1 "$GIT_REPO_URL" "$APP_NAME.tmp"
rm -rf "$APP_NAME.tmp/.git" # Remove .git for fresh init

# Move to final directory
mkdir -p "$APP_NAME"
mv "$APP_NAME.tmp/"* "$APP_NAME/" 2>/dev/null || true
mv "$APP_NAME.tmp/".* "$APP_NAME/" 2>/dev/null || true
rm -rf "$APP_NAME.tmp"

# Fix ownership
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" != "root" ] && [ "$(stat -c '%U' "$APP_NAME" 2>/dev/null || stat -f '%Su' "$APP_NAME")" = "root" ]; then
    echoc "36" "Fixing directory ownership..."
    sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$APP_NAME"
fi

echoc "32" "✔ Template cloned."

# --- Copy setup2.sh ---
cp setup/setup2.sh "$APP_NAME/"
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$APP_NAME" 2>/dev/null || chown -R "$CURRENT_USER:$CURRENT_USER" "$APP_NAME"

# Fix line endings and permissions
if command -v dos2unix &> /dev/null; then
    dos2unix "$APP_NAME/setup2.sh" > /dev/null 2>&1 || true
fi
chmod +x "$APP_NAME/setup2.sh"

echoc "32" "✔ Setup scripts prepared."
echo ""

# --- 4. Execute Setup Part 2 ---
cd "$APP_NAME"

echoc "36" "--- Executing Setup Part 2 ---"
if ! ./setup2.sh "$APP_NAME" "$DB_USER" "$DB_PASSWORD" "$DB_ROOT_PASSWORD" "$DB_DATABASE" "$DB_HOST_PORT" "$MAILPIT_SMTP_PORT" "$MAILPIT_WEB_PORT" "$ENABLE_MAILER" "$ENABLE_MERCURE"; then
    echoc "31" "============================================================"
    echoc "31" "ERROR: Setup failed."
    echoc "31" "The project directory will NOT be removed automatically."
    echoc "31" "Please check the error messages above."
    echoc "31" "============================================================"
    exit 1
fi

echoc "32" "Setup completed successfully!"
