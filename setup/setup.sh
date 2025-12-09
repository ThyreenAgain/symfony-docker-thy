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

echo "Which Symfony version do you want to use? (default: 7.4.*)"
read -r SYMFONY_VERSION
if [ -z "$SYMFONY_VERSION" ]; then
    SYMFONY_VERSION="7.4.*"
fi

echo "Which package stability do you need?"
echo "Options: dev, alpha, beta, RC, stable (default: stable)"
read -r STABILITY
if [ -z "$STABILITY" ]; then
    STABILITY="stable"
fi

echo "Symfony version set to: $SYMFONY_VERSION"
echo "Stability set to: $STABILITY"
export SYMFONY_VERSION
export STABILITY

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
            echoc "32" "✓ Port $input_port is available and will be used" >&2
            selected_port=$input_port
            echo "" >&2
            break
        else
            echo "" >&2
            echoc "31" "✗ Port not available" >&2
            echo "Finding next available port..." >&2
            local suggested=$(find_available_port $((input_port + 1)))
            echo "" >&2
            
            echoc "33" "⚠ Port $input_port is already in use." >&2
            read -p "   Do you want to use port $suggested instead? (y/n): " use_suggested >&2
            use_suggested=$(echo "$use_suggested" | tr '[:upper:]' '[:lower:]')
            echo "" >&2
            
            if [[ "$use_suggested" == "y" ]]; then
                selected_port=$suggested
                echoc "32" "✓ Using port $suggested" >&2
                echo "" >&2
                break
            else
                echoc "36" "Please enter a different port number." >&2
                echo "" >&2
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
            read -p "   Enter choice (1/2, default: 1): " MAILPIT_CHOICE
            MAILPIT_CHOICE=${MAILPIT_CHOICE:-1}
            if [[ "$MAILPIT_CHOICE" == "1" ]]; then
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

# Ask about MinIO
echoc "36" "🗄️ MinIO Object Storage:"
echoc "36" "   S3-compatible object storage for files, images, and media."
echoc "36" "   Useful for testing file upload and storage features."
echo ""
read -p "   Do you want to use MinIO for object storage? (y/n, default: n): " WANT_MINIO
WANT_MINIO=$(echo "${WANT_MINIO:-n}" | tr '[:upper:]' '[:lower:]')
echo ""

ENABLE_MINIO=n
SHARED_MINIO_CREATED=false

if [[ "$WANT_MINIO" == "y" ]]; then
    # Check for existing MinIO instances
    EXISTING_MINIO=""
    if command -v docker &> /dev/null; then
        EXISTING_MINIO=$(docker ps --filter "ancestor=minio/minio" --format "{{.Names}}: {{.Ports}}" 2>/dev/null | head -1)
    fi

    if [ -n "$EXISTING_MINIO" ]; then
        # Existing MinIO found
        echoc "33" "   ⚠ EXISTING MINIO DETECTED: $EXISTING_MINIO"
        echo ""
        echoc "32" "   💡 TIP: MinIO can be shared across ALL projects!"
        echo ""
        echoc "36" "   Choose an option:"
        echoc "36" "   1. Use the existing shared MinIO (recommended)"
        echoc "36" "   2. Create a separate MinIO for this project"
        echo ""
        read -p "   Enter choice (1/2, default: 1): " MINIO_CHOICE
        MINIO_CHOICE=${MINIO_CHOICE:-1}
        if [[ "$MINIO_CHOICE" == "1" ]]; then
            echoc "32" "   ✓ Will configure project to use existing shared MinIO"
            ENABLE_MINIO=n
        else
            echoc "36" "   Will create project-specific MinIO"
            ENABLE_MINIO=y
        fi
    else
        # No existing MinIO found
        echoc "32" "   ℹ No existing MinIO instance detected."
        echo ""
        echoc "36" "   Choose an option:"
        echoc "36" "   1. Create a SHARED MinIO (recommended) - one instance for all projects"
        echoc "36" "   2. Create MinIO inside THIS project's compose stack"
        echo ""
        read -p "   Create a shared standalone MinIO? (y/n, default: y): " CREATE_SHARED
        CREATE_SHARED=$(echo "${CREATE_SHARED:-y}" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$CREATE_SHARED" == "y" ]]; then
            echoc "36" ""
            echoc "36" "   Creating shared MinIO container..."
            
            # Get MinIO credentials first
            echo ""
            echoc "36" "--- MinIO Credentials for Shared Instance ---"
            read -p "Enter MinIO Access Key (Default: 'minioadmin'): " SHARED_MINIO_USER
            SHARED_MINIO_USER=${SHARED_MINIO_USER:-"minioadmin"}
            
            read -s -p "Enter MinIO Secret Key (Default: 'minioadmin'): " SHARED_MINIO_PASS
            echo ""
            if [ -z "$SHARED_MINIO_PASS" ]; then
                SHARED_MINIO_PASS="minioadmin"
            fi
            echo ""
            
            # Create a standalone MinIO container that persists across reboots
            if docker run -d \
                --name shared-minio \
                -p 9000:9000 \
                -p 9001:9001 \
                -e MINIO_ROOT_USER="${SHARED_MINIO_USER}" \
                -e MINIO_ROOT_PASSWORD="${SHARED_MINIO_PASS}" \
                --restart unless-stopped \
                minio/minio server /data --console-address ":9001" 2>/dev/null; then
                
                echoc "32" "   ✓ Shared MinIO created successfully!"
                echoc "32" "   API: http://localhost:9000"
                echoc "32" "   Console: http://localhost:9001"
                echoc "32" "   Username: minioadmin"
                echoc "32" "   Password: minioadmin"
                echoc "32" "   This container will be used by all your projects."
                SHARED_MINIO_CREATED=true
                ENABLE_MINIO=n
            else
                echoc "31" "   ✗ Failed to create shared MinIO (port 9000 or 9001 might be in use)"
                echoc "36" "   Falling back to project-specific MinIO..."
                ENABLE_MINIO=y
            fi
        else
            echoc "36" "   Will include MinIO in this project's compose stack"
            ENABLE_MINIO=y
        fi
    fi
else
    echoc "36" "   MinIO will not be configured for this project."
fi

echo ""

# --- Get DB Credentials (only if database selected) ---
if [[ "$DB_TYPE" != "none" ]]; then
    echo "--- Database Credentials ---"
    
    # Determine database type label and default port
    if [[ "$DB_TYPE" == "mysql" ]]; then
        DB_LABEL="MySQL"
        DEFAULT_PORT=3306
    else
        DB_LABEL="PostgreSQL"
        DEFAULT_PORT=5432
    fi
    
    # Database Name
    while true; do
        read -p "Enter $DB_LABEL Database Name (Default: '${APP_NAME}_db'): " DB_DATABASE
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
        read -p "Enter $DB_LABEL User (Default: '${DEFAULT_DB_USER}'): " DB_USER
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
    
    # Database Password
    read -s -p "Enter $DB_LABEL Password: " DB_PASSWORD
    echo ""
    if [ -z "$DB_PASSWORD" ]; then
        echoc "31" "Database password cannot be empty."
        exit 1
    fi
    
    # MySQL needs root password, PostgreSQL doesn't
    if [[ "$DB_TYPE" == "mysql" ]]; then
        read -s -p "Enter MySQL Root Password: " DB_ROOT_PASSWORD
        echo ""
        if [ -z "$DB_ROOT_PASSWORD" ]; then
            echoc "31" "Database root password cannot be empty."
            exit 1
        fi
    else
        DB_ROOT_PASSWORD=""
    fi
else
    # Set empty values when no database
    DB_DATABASE=""
    DB_USER=""
    DB_PASSWORD=""
    DB_ROOT_PASSWORD=""
fi

echo ""
echoc "36" "--- Port Configuration ---"
if [[ "$DB_TYPE" == "mysql" ]]; then
    echoc "36" "Standard ports: HTTP=80, HTTPS=443, MySQL=3306"
elif [[ "$DB_TYPE" == "postgres" ]] || [[ "$DB_TYPE" == "postgis" ]]; then
    echoc "36" "Standard ports: HTTP=80, HTTPS=443, PostgreSQL=5432"
else
    echoc "36" "Standard ports: HTTP=80, HTTPS=443"
fi
if [[ "$ENABLE_MAILER" == "y" ]]; then
    echoc "36" "                Mailpit SMTP=1025, Mailpit Web=8025"
fi
if [[ "$ENABLE_MINIO" == "y" ]]; then
    echoc "36" "                MinIO API=9000, MinIO Console=9001"
fi
echoc "36" "Change these ONLY if you run multiple projects simultaneously."
echo ""


# --- Get Unique Ports with availability checking ---
# 1. HTTP Port
HTTP_PORT=$(prompt_for_port "Webserver HTTP" 8080)
# 2. HTTPS Port
HTTPS_PORT=$(prompt_for_port "Webserver HTTPS" 8443)

# 3. Database Port
if [[ "$DB_TYPE" != "none" ]]; then
    if [[ "$DB_TYPE" == "mysql" ]]; then
        DB_HOST_PORT=$(prompt_for_port "MySQL" 3306)
    else
        DB_HOST_PORT=$(prompt_for_port "PostgreSQL" 5432)
    fi
else
    DB_HOST_PORT=""
fi

# 4. Mailpit Ports (if enabled)
if [[ "$ENABLE_MAILER" == "y" ]]; then
    MAILPIT_SMTP_PORT=$(prompt_for_port "Mailpit SMTP" 1025)
    MAILPIT_WEB_PORT=$(prompt_for_port "Mailpit Web UI" 8025)
else
    MAILPIT_SMTP_PORT=""
    MAILPIT_WEB_PORT=""
fi

# 5. MinIO Ports (only if project-specific MinIO)
if [[ "$ENABLE_MINIO" == "y" ]]; then
    MINIO_API_PORT=$(prompt_for_port "MinIO API" 9000)
    MINIO_CONSOLE_PORT=$(prompt_for_port "MinIO Console" 9001)
else
    # Using shared MinIO - no custom ports needed
    MINIO_API_PORT=""
    MINIO_CONSOLE_PORT=""
fi

# 6. MinIO Credentials (if using MinIO - shared or project-specific)
if [[ "$WANT_MINIO" == "y" ]]; then
    echo ""
    echoc "36" "--- MinIO Credentials ---"
    
    # MinIO Access Key
    read -p "Enter MinIO Access Key (Default: 'minioadmin'): " MINIO_ROOT_USER
    MINIO_ROOT_USER=${MINIO_ROOT_USER:-"minioadmin"}
    
    # MinIO Secret Key
    read -s -p "Enter MinIO Secret Key (Default: 'minioadmin'): " MINIO_ROOT_PASSWORD
    echo ""
    if [ -z "$MINIO_ROOT_PASSWORD" ]; then
        MINIO_ROOT_PASSWORD="minioadmin"
    fi
    
    echoc "32" "✓ MinIO credentials configured"
    echo ""
else
    MINIO_ROOT_USER=""
    MINIO_ROOT_PASSWORD=""
fi

# Export for setup2.sh
export HTTP_PORT
export HTTPS_PORT
export DB_HOST_PORT
export MAILPIT_SMTP_PORT
export MAILPIT_WEB_PORT
export MINIO_API_PORT
export MINIO_CONSOLE_PORT
export MINIO_ROOT_USER
export MINIO_ROOT_PASSWORD

echo ""
echoc "32" "All configuration gathered. Starting setup..."
echo ""

# --- 3. Determine Project Location ---
# Always clone in /tmp to avoid permission issues - NO SUDO NEEDED
WORK_DIR=$(mktemp -d)
PROJECT_DIR="$WORK_DIR/$APP_NAME"

echoc "33" "NOTE: Project will be created in /tmp for safety."
echoc "33" "This approach avoids sudo and permission issues."
echo ""

echo "--- Cloning Symfony Docker Template ---"
echoc "36" "Cloning repository: $GIT_REPO_URL"
echoc "36" "Working in temporary directory: $PROJECT_DIR"
echoc "36" "This approach avoids sudo and permission issues."

# Clone to temp work directory (ALWAYS in /tmp, safe for all filesystems)
git clone --depth 1 "$GIT_REPO_URL" "$PROJECT_DIR"
rm -rf "$PROJECT_DIR/.git" # Remove .git for fresh init

echoc "32" "✔ Template cloned to temporary location."

# --- Copy setup2.sh ---
cp setup/setup2.sh "$PROJECT_DIR/"

# Fix line endings and permissions
if command -v dos2unix &> /dev/null; then
    dos2unix "$PROJECT_DIR/setup2.sh" > /dev/null 2>&1 || true
fi
chmod +x "$PROJECT_DIR/setup2.sh"

# --- Copy move-to.sh helper script ---
mkdir -p "$PROJECT_DIR/scripts"
cp scripts/move-to.sh "$PROJECT_DIR/scripts/"

# Fix line endings and permissions
if command -v dos2unix &> /dev/null; then
    dos2unix "$PROJECT_DIR/scripts/move-to.sh" > /dev/null 2>&1 || true
fi
chmod +x "$PROJECT_DIR/scripts/move-to.sh"

echoc "32" "✔ Setup scripts prepared."
echo ""

# --- 4. Execute Setup Part 2 in temp directory---
cd "$PROJECT_DIR"

echoc "36" "--- Executing Setup Part 2 ---"
if ! ./setup2.sh "$APP_NAME" "$DB_USER" "$DB_PASSWORD" "$DB_ROOT_PASSWORD" "$DB_DATABASE" "$DB_HOST_PORT" "$MAILPIT_SMTP_PORT" "$MAILPIT_WEB_PORT" "$ENABLE_MAILER" "$ENABLE_MERCURE" "$DB_TYPE" "$HTTP_PORT" "$HTTPS_PORT" "$ENABLE_MINIO" "$MINIO_API_PORT" "$MINIO_CONSOLE_PORT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"; then
    echoc "31" "============================================================"
    echoc "31" "ERROR: Setup failed."
    echoc "31" "Cleaning up temporary directory..."
    cd /
    rm -rf "$WORK_DIR" 2>/dev/null || true
    echoc "31" "============================================================"
    exit 1
fi

echoc "32" "✔ Setup part 2 completed successfully!"
echo ""

# --- 5. Final Success Message ---
echo ""
echoc "32" "=============================================================="
echoc "32" "✅ Setup completed successfully!"
echoc "32" "=============================================================="
echo ""
echoc "32" "Project location: $PROJECT_DIR"
echo ""
echoc "33" "To move to your desired location:"
echoc "33" "  cp -r $PROJECT_DIR /your/desired/location/project_name"
echoc "33" "Or use the convenience script:"
echoc "33" "  $PROJECT_DIR/scripts/move-to.sh /your/desired/location/project_name"
echo ""
echoc "32" "Docker container is started Next time just use:"
echoc "32" "  cd $PROJECT_DIR"
echoc "32" "  make up"
echo ""
echoc "33" "Need help with TLS/SSL setup? Follow the guide at:"
echoc "33" "https://github.com/ThyreenAgain/symfony-docker-thy/blob/main/docs/tls.md"
echo ""
