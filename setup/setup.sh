#!/bin/bash
#
# Symfony Docker Environment Setup Script
#
# This script performs the following actions:
# 1. Checks for Docker, Docker Compose, and Git.
# 2. Prompts the user for custom container names, database credentials, and UNIQUE ports.
# 3. **Clones the hardcoded custom Git repository (your fork).**
# 4. Calls setup2.sh (the main configuration and installation script) with all inputs.
# 5. Catches failures from setup2.sh and cleans up the project directory.

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

# Check for Git, which is now mandatory
if ! command -v git &> /dev/null; then
    echoc "31" "ERROR: 'git' command not found. Please install it to proceed with project setup."
    exit 1
fi

echoc "32" "✔ Docker, Docker Compose, and Git found."
echo ""

# --- 2. User Input (Database and Ports) ---
echo "--- Gathering Project Details ---"

# --- Get Project Name / Container Prefix ---
read -p "Enter a unique project/container prefix (e.g., 'invoice_app'): " APP_CONTAINER_NAME

if [ -z "$APP_CONTAINER_NAME" ]; then
    echoc "31" "Project prefix cannot be empty."
    exit 1
fi

# --- Set Custom Git Repository URL (Hardcoded) ---
GIT_REPO_URL="https://github.com/ThyreenAgain/symfony-docker-thy"
echoc "36" "Using hardcoded Git repository: $GIT_REPO_URL"

# --- Get DB Credentials ---
read -p "Enter MySQL Database Name (e.g., '${APP_CONTAINER_NAME}_db'): " DB_DATABASE
DB_DATABASE=${DB_DATABASE:-"${APP_CONTAINER_NAME}_db"}

# --- Set default MySQL User based on the project name (lowercase) ---
DEFAULT_DB_USER=$(echo "${APP_CONTAINER_NAME}_db_user" | tr '[:upper:]' '[:lower:]')
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
echoc "36" "--- Unique Port Configuration ---"
echoc "36" "Note: Standard defaults are shown below. Change them ONLY if you run multiple projects simultaneously."

# --- Get Unique DB Host Port (Default: 3306) ---
read -p "Enter UNIQUE Host Port for MySQL (Default: 3306): " DB_HOST_PORT
DB_HOST_PORT=${DB_HOST_PORT:-3306} 

# Basic validation for DB Port
if ! [[ "$DB_HOST_PORT" =~ ^[0-9]+$ ]] || [ "$DB_HOST_PORT" -lt 1024 ] || [ "$DB_HOST_PORT" -gt 65535 ]; then
    echoc "31" "Invalid port number. Must be between 1024 and 65535."
    exit 1
fi

# --- Get Unique Mailpit SMTP Port (Default: 1025) ---
read -p "Enter UNIQUE Host Port for Mailpit SMTP (Default: 1025): " MAILPIT_SMTP_PORT
MAILPIT_SMTP_PORT=${MAILPIT_SMTP_PORT:-1025} 

# Basic validation for SMTP Port
if ! [[ "$MAILPIT_SMTP_PORT" =~ ^[0-9]+$ ]] || [ "$MAILPIT_SMTP_PORT" -lt 1024 ] || [ "$MAILPIT_SMTP_PORT" -gt 65535 ]; then
    echoc "31" "Invalid port number."
    exit 1
fi

# --- Get Unique Mailpit Web Port (Default: 8025) ---
read -p "Enter UNIQUE Host Port for Mailpit Web UI (Default: 8025): " MAILPIT_WEB_PORT
MAILPIT_WEB_PORT=${MAILPIT_WEB_PORT:-8025} 

# Basic validation for Web Port
if ! [[ "$MAILPIT_WEB_PORT" =~ ^[0-9]+$ ]] || [ "$MAILPIT_WEB_PORT" -lt 1024 ] || [ "$MAILPIT_WEB_PORT" -gt 65535 ]; then
    echoc "31" "Invalid port number."
    exit 1
fi

echo ""
echoc "32" "All configuration gathered. Starting setup..."
echo ""

# --- 3. Create Project Folder and Execute Setup2 ---

# Create project directory
if [ -d "$APP_CONTAINER_NAME" ]; then
    echoc "31" "ERROR: Directory '${APP_CONTAINER_NAME}' already exists. Please choose a different project prefix."
    exit 1
fi

echo "--- Cloning custom Symfony Docker project and setting up configuration ---"

# --- Clone the actual Symfony project structure from Git ---
# This clones the user's custom repository which includes the DOCKERFILE, compose files, and frankenphp configs.
echoc "36" "Cloning Git repository '$GIT_REPO_URL' (via temporary directory)..."
git clone --depth 1 "$GIT_REPO_URL" "$APP_CONTAINER_NAME.tmp"
rm -rf "$APP_CONTAINER_NAME.tmp/.git" # Remove .git directory for fresh init later

# Create the main directory and move the contents
mkdir -p "$APP_CONTAINER_NAME"
# Use '2>/dev/null || true' to suppress errors if temp dir is empty/has specific file patterns
mv "$APP_CONTAINER_NAME.tmp/"* "$APP_CONTAINER_NAME/" 2>/dev/null || true
mv "$APP_CONTAINER_NAME.tmp/".* "$APP_CONTAINER_NAME/" 2>/dev/null || true
rm -rf "$APP_CONTAINER_NAME.tmp" # Remove temp directory

# IMPORTANT: Ensure the folder is owned by the current non-root user.
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" != "root" ] && [ "$(stat -c '%U' "$APP_CONTAINER_NAME")" = "root" ]; then
    echoc "36" "Fixing directory ownership to user '$CURRENT_USER'..."
    sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$APP_CONTAINER_NAME"
    echoc "32" "✔ Ownership corrected."
fi

echoc "32" "✔ Symfony project structure initialized."

# --- Copy Setup Part 2 Script ---
# This is the only file still copied locally, as it contains dynamic configuration logic.
cp setup2.sh "$APP_CONTAINER_NAME/" # Copy the second setup script

# Re-apply ownership
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$APP_CONTAINER_NAME"
echoc "32" "✔ Setup script copied and permissions secured."

# --- Fix permissions and line endings for setup2.sh ---
echoc "36" "Ensuring setup2.sh is executable and has correct line endings..."
if command -v dos2unix &> /dev/null; then
    sudo dos2unix "$APP_CONTAINER_NAME/setup2.sh" > /dev/null 2>&1
    echoc "32" "✔ Line endings fixed."
fi
sudo chmod +x "$APP_CONTAINER_NAME/setup2.sh"
echoc "32" "✔ Execute permission set."

# Move into the new directory
cd "$APP_CONTAINER_NAME"

echoc "36" "--- Handing off to Setup Part 2 ---"
exit 1
# --- 4. Execute Setup Part 2 and Catch Failures ---
if ! ./setup2.sh "$APP_CONTAINER_NAME" "$DB_USER" "$DB_PASSWORD" "$DB_ROOT_PASSWORD" "$DB_DATABASE" "$DB_HOST_PORT" "$MAILPIT_SMTP_PORT" "$MAILPIT_WEB_PORT"; then
    # If setup2.sh fails, cleanup is handled by setup2.sh trap.
    
    echoc "31" "============================================================"
    echoc "31" "ERROR: Setup Part 2 failed."
    echoc "31" "Rollback: Cleaning up project directory..."
    
    # Go back to the parent directory
    cd ..
    
    # Remove the entire project folder
    #rm -rf "$APP_CONTAINER_NAME"
    
    echoc "31" "Rollback: Project directory '${APP_CONTAINER_NAME}' has been removed."
    echoc "31" "============================================================"
    exit 1
fi

# If setup2.sh succeeds, setup.sh exits normally.
