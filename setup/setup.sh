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
#
# Usage: ./setup.sh [--verbose]

set -e # Exit immediately if a command exits with a non-zero status

# Check for verbose flag
VERBOSE=false
if [[ "$1" == "--verbose" ]]; then
    VERBOSE=true
fi

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

# --- Helper function to check if port is available (silent mode) ---
check_port() {
    local port=$1
    local service_name=$2
    local in_wsl=false
    
    # Detect WSL environment
    if is_wsl; then
        in_wsl=true
        if [ "$VERBOSE" = true ]; then
            echoc "36" "🐧 WSL Environment Detected - Checking both WSL and Windows ports..."
        fi
    fi
    
    # Check if port is in use in WSL/Linux
    local wsl_port_used=false
    local detection_method="none"
    
    if command -v lsof &> /dev/null; then
        detection_method="lsof"
        if [ "$VERBOSE" = true ]; then
            echoc "36" "   📊 Using 'lsof' for WSL port detection..."
        fi
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 ; then
            wsl_port_used=true
            if [ "$VERBOSE" = true ]; then
                local process=$(lsof -Pi :$port -sTCP:LISTEN 2>/dev/null | grep LISTEN | awk '{print $1}' | head -1)
                echoc "33" "   ⚠ Port $port in use in WSL by: $process"
            fi
        else
            if [ "$VERBOSE" = true ]; then
                echoc "32" "   ✓ Port $port is available in WSL (lsof check)"
            fi
        fi
    elif command -v netstat &> /dev/null; then
        detection_method="netstat"
        if [ "$VERBOSE" = true ]; then
            echoc "36" "   📊 Using 'netstat' for WSL port detection..."
        fi
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            wsl_port_used=true
            if [ "$VERBOSE" = true ]; then
                echoc "33" "   ⚠ Port $port in use in WSL (netstat)"
            fi
        else
            if [ "$VERBOSE" = true ]; then
                echoc "32" "   ✓ Port $port is available in WSL (netstat check)"
            fi
        fi
    elif command -v ss &> /dev/null; then
        detection_method="ss"
        if [ "$VERBOSE" = true ]; then
            echoc "36" "   📊 Using 'ss' for WSL port detection..."
        fi
        if ss -tuln 2>/dev/null | grep -q ":$port "; then
            wsl_port_used=true
            if [ "$VERBOSE" = true ]; then
                echoc "33" "   ⚠ Port $port in use in WSL (ss)"
            fi
        else
            if [ "$VERBOSE" = true ]; then
                echoc "32" "   ✓ Port $port is available in WSL (ss check)"
            fi
        fi
    fi
    
    # If in WSL, also check Windows host ports
    if [ "$in_wsl" = true ]; then
        if [ "$VERBOSE" = true ]; then
            echoc "36" "   🪟 Checking Windows host ports via PowerShell..."
        fi
        
        # Try to query Windows ports using PowerShell
        if command -v powershell.exe &> /dev/null; then
            local ps_result=$(powershell.exe -Command "Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1" 2>/dev/null)
            
            if [ -n "$ps_result" ] && [ "$ps_result" != "" ]; then
                if [ "$VERBOSE" = true ]; then
                    echoc "33" "   ⚠ Port $port is in use on Windows host!"
                    echoc "33" "   💡 This port is bound by a Windows application (e.g., Docker Desktop)"
                fi
                return 1
            else
                if [ "$VERBOSE" = true ]; then
                    echoc "32" "   ✓ Port $port is available on Windows host"
                fi
            fi
        fi
        
        # Also check Docker containers for port mappings
        if [ "$VERBOSE" = true ]; then
            echoc "36" "   🐳 Checking Docker Desktop for containers using port $port..."
        fi
        if command -v docker &> /dev/null; then
            local docker_port_check=$(docker ps --format "{{.Names}}: {{.Ports}}" 2>/dev/null | grep -E ":${port}->|:${port}/" | head -1)
            
            if [ -n "$docker_port_check" ]; then
                if [ "$VERBOSE" = true ]; then
                    echoc "33" "   ⚠ Port $port is being used by a Docker container!"
                    echoc "33" "   Container: $docker_port_check"
                fi
                return 1
            else
                if [ "$VERBOSE" = true ]; then
                    echoc "32" "   ✓ No Docker containers using port $port"
                fi
            fi
        fi
    fi
    
    # Return result based on detection
    if [ "$wsl_port_used" = true ]; then
        return 1
    fi
    
    return 0
}

# --- Helper function to find next available port ---
find_available_port() {
    local start_port=$1
    local max_attempts=100
    
    for ((port=start_port; port<start_port+max_attempts; port++)); do
        if check_port $port "temp"; then
            echo $port
            return 0
        fi
    done
    
    echo $((start_port + 1000))
    return 0
}

# --- Helper function to prompt for port with auto-suggestion ---
prompt_for_port() {
    local service_name=$1
    local default_port=$2
    local selected_port=""
    
    while true; do
        read -p "Enter Host Port for $service_name (Default: $default_port): " input_port
        input_port=${input_port:-$default_port}
        
        # Validate port number
        if ! [[ "$input_port" =~ ^[0-9]+$ ]] || [ "$input_port" -lt 1024 ] || [ "$input_port" -gt 65535 ]; then
            echoc "31" "⚠ Invalid port. Must be between 1024 and 65535."
            echo ""
            continue
        fi
        
        # Show checking indicator and flush output to stderr for immediate display
        echo "Checking if port $input_port is available..." >&2
        
        # Check if port is available
        if check_port $input_port "$service_name"; then
            echo "" >&2
            echoc "32" "✓ Port $input_port is available and will be used"
            selected_port=$input_port
            echo ""
            break
        else
            echo "" >&2
            echoc "31" "✗ Port $input_port is already in use" >&2
            echo "Finding next available port..." >&2
            local suggested=$(find_available_port $((input_port + 1)))
            echo "" >&2
            
            echoc "33" "⚠ Port $input_port is already in use."
            read -p "   Do you want to use port $suggested instead? (y/n): " use_suggested
            use_suggested=$(echo "$use_suggested" | tr '[:upper:]' '[:lower:]')
            echo ""
            
            if [[ "$use_suggested" == "y" ]]; then
                selected_port=$suggested
                echoc "32" "✓ Using port $suggested"
                echo ""
                break
            else
                echoc "36" "Please enter a different port number."
                echo ""
            fi
            # Loop continues to ask for another port
        fi
    done
    
    echo $selected_port
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
while true; do
    read -p "Enter a unique project name (e.g., 'invoice_app'): " APP_NAME
    
    if [ -z "$APP_NAME" ]; then
        echoc "31" "⚠ Project name cannot be empty."
        continue
    fi
    
    # Convert to lowercase, convert hyphens to underscores, sanitize
    SANITIZED_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr '-' '_' | sed 's/[^a-z0-9_]//g')
    
    if [ "$APP_NAME" != "$SANITIZED_NAME" ]; then
        echoc "33" "⚠ Project name contained invalid characters. Converting to: $SANITIZED_NAME"
        APP_NAME="$SANITIZED_NAME"
    fi
    
    # Check if name starts with letter or underscore (Docker requirement)
    if ! [[ "$APP_NAME" =~ ^[a-z_] ]]; then
        echoc "31" "⚠ Project name must start with a letter or underscore."
        continue
    fi
    
    if [ -z "$APP_NAME" ]; then
        echoc "31" "⚠ Project name became empty after sanitization."
        continue
    fi
    
    echoc "32" "✓ Project name: $APP_NAME"
    break
done

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
echo ""
read -p "   Do you want to use Mailpit for email testing? (y/n, default: y): " WANT_MAILPIT
WANT_MAILPIT=$(echo "${WANT_MAILPIT:-y}" | tr '[:upper:]' '[:lower:]')
echo ""

ENABLE_MAILER=n
SHARED_MAILPIT_CREATED=false

if [[ "$WANT_MAILPIT" == "y" ]]; then
    # Check for existing Mailpit instances
    EXISTING_MAILPIT=""
    if command -v docker &> /dev/null; then
        EXISTING_MAILPIT=$(docker ps --filter "ancestor=axllent/mailpit" --format "{{.Names}}: {{.Ports}}" 2>/dev/null | head -1)
    fi

    if [ -n "$EXISTING_MAILPIT" ]; then
        # Existing Mailpit found
        echoc "33" "   ⚠ EXISTING MAILPIT DETECTED: $EXISTING_MAILPIT"
        echo ""
        echoc "32" "   💡 TIP: Mailpit is stateless - you can share ONE instance across ALL projects!"
        echo ""
        echoc "36" "   Choose an option:"
        echoc "36" "   1. Use the existing shared Mailpit (recommended)"
        echoc "36" "   2. Create a separate Mailpit for this project"
        echo ""
        read -p "   Use existing shared Mailpit? (y/n, default: y): " USE_EXISTING
        USE_EXISTING=$(echo "${USE_EXISTING:-y}" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$USE_EXISTING" == "y" ]]; then
            echoc "32" "   ✓ Will configure project to use existing shared Mailpit"
            ENABLE_MAILER=n
        else
            echoc "36" "   Will create project-specific Mailpit"
            ENABLE_MAILER=y
        fi
    else
        # No existing Mailpit found
        echoc "32" "   ℹ No existing Mailpit instance detected."
        echo ""
        echoc "36" "   Choose an option:"
        echoc "36" "   1. Create a SHARED Mailpit (recommended) - one instance for all projects"
        echoc "36" "   2. Create Mailpit inside THIS project's compose stack"
        echo ""
        read -p "   Create a shared standalone Mailpit? (y/n, default: y): " CREATE_SHARED
        CREATE_SHARED=$(echo "${CREATE_SHARED:-y}" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$CREATE_SHARED" == "y" ]]; then
            echoc "36" ""
            echoc "36" "   Creating shared Mailpit container..."
            
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
            echoc "36" "   Will include Mailpit in this project's compose stack"
            ENABLE_MAILER=y
        fi
    fi
else
    echoc "36" "   Mailpit will not be configured for this project."
fi

echo ""

# Ask about Mercure
echoc "36" "⚡ Mercure Hub:"
echoc "36" "   Real-time messaging for live updates (Server-Sent Events)."
echoc "36" "   Only needed if you're building apps with real-time features."
read -p "   Enable Mercure? (y/n, default: n): " ENABLE_MERCURE
ENABLE_MERCURE=$(echo "${ENABLE_MERCURE:-n}" | tr '[:upper:]' '[:lower:]')
echo ""

# --- Get DB Credentials ---
echo "--- Database Configuration ---"

# Database Name
while true; do
    read -p "Enter MySQL Database Name (Default: '${APP_NAME}_db'): " DB_DATABASE
    DB_DATABASE=${DB_DATABASE:-"${APP_NAME}_db"}
    
    # Sanitize: lowercase, convert hyphens to underscores, only alphanumeric and underscore
    SANITIZED_DB=$(echo "$DB_DATABASE" | tr '[:upper:]' '[:lower:]' | tr '-' '_' | sed 's/[^a-z0-9_]//g')
    
    if [ "$DB_DATABASE" != "$SANITIZED_DB" ]; then
        echoc "33" "⚠ Database name contained invalid characters. Converting to: $SANITIZED_DB"
        DB_DATABASE="$SANITIZED_DB"
    fi
    
    if [ -z "$DB_DATABASE" ]; then
        echoc "31" "⚠ Database name cannot be empty."
        continue
    fi
    
    echoc "32" "✓ Database name: $DB_DATABASE"
    break
done

# Database User
DEFAULT_DB_USER=$(echo "${APP_NAME}_user" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]//g')
while true; do
    read -p "Enter MySQL User (Default: '${DEFAULT_DB_USER}'): " DB_USER
    DB_USER=${DB_USER:-"${DEFAULT_DB_USER}"}
    
    # Sanitize: lowercase, convert hyphens to underscores, only alphanumeric and underscore
    SANITIZED_USER=$(echo "$DB_USER" | tr '[:upper:]' '[:lower:]' | tr '-' '_' | sed 's/[^a-z0-9_]//g')
    
    if [ "$DB_USER" != "$SANITIZED_USER" ]; then
        echoc "33" "⚠ Username contained invalid characters. Converting to: $SANITIZED_USER"
        DB_USER="$SANITIZED_USER"
    fi
    
    if [ -z "$DB_USER" ]; then
        echoc "31" "⚠ Username cannot be empty."
        continue
    fi
    
    echoc "32" "✓ Database user: $DB_USER"
    break
done

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
DB_HOST_PORT=$(prompt_for_port "MySQL" 3306)

# Only ask for Mailpit ports if enabled
if [[ "$ENABLE_MAILER" =~ ^[Yy]$ ]]; then
    MAILPIT_SMTP_PORT=$(prompt_for_port "Mailpit SMTP" 1025)
    MAILPIT_WEB_PORT=$(prompt_for_port "Mailpit Web UI" 8025)
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
