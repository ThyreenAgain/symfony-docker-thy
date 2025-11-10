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

# --- Helper function to detect if running in WSL ---
is_wsl() {
    if [ -f /proc/version ] && grep -qi microsoft /proc/version; then
        return 0
    fi
    return 1
}

# --- Helper function to check if port is available ---
check_port() {
    local port=$1
    local service_name=$2
    local in_wsl=false
    
    # Detect WSL environment
    if is_wsl; then
        in_wsl=true
        echoc "36" "🐧 WSL Environment Detected - Checking both WSL and Windows ports..."
    fi
    
    # Check if port is in use in WSL/Linux
    local wsl_port_used=false
    local detection_method="none"
    
    if command -v lsof &> /dev/null; then
        detection_method="lsof"
        echoc "36" "   📊 Using 'lsof' for WSL port detection..."
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 ; then
            wsl_port_used=true
            # Try to identify what's using the port
            local process=$(lsof -Pi :$port -sTCP:LISTEN 2>/dev/null | grep LISTEN | awk '{print $1}' | head -1)
            echoc "33" "   ⚠ Port $port in use in WSL by: $process"
        else
            echoc "32" "   ✓ Port $port is available in WSL (lsof check)"
        fi
    elif command -v netstat &> /dev/null; then
        detection_method="netstat"
        echoc "36" "   📊 Using 'netstat' for WSL port detection..."
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            wsl_port_used=true
            echoc "33" "   ⚠ Port $port in use in WSL (netstat)"
        else
            echoc "32" "   ✓ Port $port is available in WSL (netstat check)"
        fi
    elif command -v ss &> /dev/null; then
        detection_method="ss"
        echoc "36" "   📊 Using 'ss' for WSL port detection..."
        if ss -tuln 2>/dev/null | grep -q ":$port "; then
            wsl_port_used=true
            echoc "33" "   ⚠ Port $port in use in WSL (ss)"
        else
            echoc "32" "   ✓ Port $port is available in WSL (ss check)"
        fi
    else
        echoc "33" "   ⚠ No port detection tool found (lsof, netstat, ss)"
    fi
    
    # If in WSL, also check Windows host ports
    if [ "$in_wsl" = true ]; then
        echoc "36" "   🪟 Checking Windows host ports via PowerShell..."
        
        # Try to query Windows ports using PowerShell
        if command -v powershell.exe &> /dev/null; then
            # Check if port is in use on Windows host
            local ps_result=$(powershell.exe -Command "Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1" 2>/dev/null)
            
            if [ -n "$ps_result" ] && [ "$ps_result" != "" ]; then
                echoc "33" "   ⚠ Port $port is in use on Windows host!"
                echoc "33" "   💡 This port is bound by a Windows application (e.g., Docker Desktop)"
                echoc "33" "   💡 WSL cannot detect Windows host ports - this is the root cause!"
                return 1
            else
                echoc "32" "   ✓ Port $port is available on Windows host"
            fi
        else
            echoc "33" "   ⚠ PowerShell not available - cannot check Windows ports"
            echoc "36" "   💡 Install PowerShell in WSL or run script from Windows"
        fi
        
        # Also check Docker containers for port mappings
        echoc "36" "   🐳 Checking Docker Desktop for containers using port $port..."
        if command -v docker &> /dev/null; then
            # Check if any Docker container has this port mapped (either as host or container port)
            local docker_port_check=$(docker ps --format "{{.Names}}: {{.Ports}}" 2>/dev/null | grep -E ":${port}->|:${port}/" | head -1)
            
            if [ -n "$docker_port_check" ]; then
                echoc "33" "   ⚠ Port $port is being used by a Docker container!"
                echoc "33" "   Container: $docker_port_check"
                echoc "33" "   💡 Docker Desktop port mappings detected - choose a different port"
                return 1
            else
                echoc "32" "   ✓ No Docker containers using port $port"
            fi
        fi
    fi
    
    # Return result based on detection
    if [ "$wsl_port_used" = true ]; then
        echoc "33" "⚠ Warning: Port $port is already in use by another service!"
        return 1
    fi
    
    return 0
}

# --- Helper function to suggest next available port ---
suggest_port() {
    local start_port=$1
    local max_attempts=100
    
    for ((port=start_port; port<start_port+max_attempts; port++)); do
        if check_port $port "temp" 2>/dev/null; then
            echo $port
            return 0
        fi
    done
    
    echo $((start_port + 1000))
    return 0
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

# Check for existing Mailpit instances
EXISTING_MAILPIT=""
SHARED_MAILPIT_CREATED=false
if command -v docker &> /dev/null; then
    EXISTING_MAILPIT=$(docker ps --filter "ancestor=axllent/mailpit" --format "{{.Names}}: {{.Ports}}" 2>/dev/null | head -1)
fi

# Ask about Mailer
echoc "36" "📧 Mailer (Mailpit):"
echoc "36" "   Email testing service with web UI to catch and inspect emails."
echoc "36" "   Useful for testing email functionality in development."
echo ""

if [ -n "$EXISTING_MAILPIT" ]; then
    echoc "33" "   ⚠ EXISTING MAILPIT DETECTED: $EXISTING_MAILPIT"
    echo ""
    echoc "32" "   💡 TIP: Mailpit is stateless - you can share ONE instance across ALL projects!"
    echoc "36" "   Recommended: Skip Mailpit here and use the existing shared instance."
    echo ""
    read -p "   Enable Mailpit for THIS project? (y/n, default: n): " ENABLE_MAILER
    ENABLE_MAILER=${ENABLE_MAILER:-n}
else
    echoc "32" "   ℹ No existing Mailpit instance detected."
    echoc "36" "   You have two options:"
    echoc "36" "   1. Create a SHARED Mailpit (recommended) - one instance for all projects"
    echoc "36" "   2. Include Mailpit in THIS project's compose stack"
    echo ""
    read -p "   Create a shared standalone Mailpit container? (y/n, default: y): " CREATE_SHARED_MAILPIT
    CREATE_SHARED_MAILPIT=${CREATE_SHARED_MAILPIT:-y}
    
    if [[ "$CREATE_SHARED_MAILPIT" =~ ^[Yy]$ ]]; then
        echoc "36" ""
        echoc "36" "Creating shared Mailpit container..."
        
        # Create a standalone Mailpit container that persists across reboots
        if docker run -d \
            --name shared-mailpit \
            -p 1025:1025 \
            -p 8025:8025 \
            --restart unless-stopped \
            axllent/mailpit 2>/dev/null; then
            
            echoc "32" "   ✓ Shared Mailpit created successfully!"
            echoc "32" "   SMTP: localhost:1025"
            echoc "32" "   Web UI: http://localhost:8025"
            echoc "32" "   This container will be used by all your projects."
            SHARED_MAILPIT_CREATED=true
            ENABLE_MAILER=n
        else
            echoc "31" "   ✗ Failed to create shared Mailpit (port 1025 or 8025 might be in use)"
            echoc "36" "   Falling back to project-specific Mailpit..."
            ENABLE_MAILER=y
        fi
    else
        echoc "36" "   Including Mailpit in this project's compose stack..."
        ENABLE_MAILER=y
    fi
fi

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

# --- Get Unique Ports with availability checking ---
while true; do
    read -p "Enter Host Port for MySQL (Default: 3306): " DB_HOST_PORT
    DB_HOST_PORT=${DB_HOST_PORT:-3306}
    
    if ! [[ "$DB_HOST_PORT" =~ ^[0-9]+$ ]] || [ "$DB_HOST_PORT" -lt 1024 ] || [ "$DB_HOST_PORT" -gt 65535 ]; then
        echoc "31" "Invalid port number. Must be between 1024 and 65535."
        continue
    fi
    
    if check_port $DB_HOST_PORT "MySQL"; then
        echoc "32" "✓ Port $DB_HOST_PORT is available"
        break
    else
        SUGGESTED_PORT=$(suggest_port $DB_HOST_PORT)
        echoc "36" "   Suggestion: Try port $SUGGESTED_PORT"
        read -p "   Try again with a different port? (y/n): " retry
        if [[ ! "$retry" =~ ^[Yy]$ ]]; then
            echoc "31" "Cannot proceed with port $DB_HOST_PORT already in use."
            exit 1
        fi
    fi
done

# Only ask for Mailpit ports if enabled
if [[ "$ENABLE_MAILER" =~ ^[Yy]$ ]]; then
    while true; do
        read -p "Enter Host Port for Mailpit SMTP (Default: 1025): " MAILPIT_SMTP_PORT
        MAILPIT_SMTP_PORT=${MAILPIT_SMTP_PORT:-1025}
        
        if ! [[ "$MAILPIT_SMTP_PORT" =~ ^[0-9]+$ ]] || [ "$MAILPIT_SMTP_PORT" -lt 1024 ] || [ "$MAILPIT_SMTP_PORT" -gt 65535 ]; then
            echoc "31" "Invalid port number."
            continue
        fi
        
        if check_port $MAILPIT_SMTP_PORT "Mailpit SMTP"; then
            echoc "32" "✓ Port $MAILPIT_SMTP_PORT is available"
            break
        else
            SUGGESTED_PORT=$(suggest_port $MAILPIT_SMTP_PORT)
            echoc "36" "   Suggestion: Try port $SUGGESTED_PORT"
            read -p "   Try again with a different port? (y/n): " retry
            if [[ ! "$retry" =~ ^[Yy]$ ]]; then
                echoc "31" "Cannot proceed with port $MAILPIT_SMTP_PORT already in use."
                exit 1
            fi
        fi
    done
    
    while true; do
        read -p "Enter Host Port for Mailpit Web UI (Default: 8025): " MAILPIT_WEB_PORT
        MAILPIT_WEB_PORT=${MAILPIT_WEB_PORT:-8025}
        
        if ! [[ "$MAILPIT_WEB_PORT" =~ ^[0-9]+$ ]] || [ "$MAILPIT_WEB_PORT" -lt 1024 ] || [ "$MAILPIT_WEB_PORT" -gt 65535 ]; then
            echoc "31" "Invalid port number."
            continue
        fi
        
        if check_port $MAILPIT_WEB_PORT "Mailpit Web UI"; then
            echoc "32" "✓ Port $MAILPIT_WEB_PORT is available"
            break
        else
            SUGGESTED_PORT=$(suggest_port $MAILPIT_WEB_PORT)
            echoc "36" "   Suggestion: Try port $SUGGESTED_PORT"
            read -p "   Try again with a different port? (y/n): " retry
            if [[ ! "$retry" =~ ^[Yy]$ ]]; then
                echoc "31" "Cannot proceed with port $MAILPIT_WEB_PORT already in use."
                exit 1
            fi
        fi
    done
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
