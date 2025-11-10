#!/bin/bash
#
# Symfony Docker Template - Standalone Installer
#
# This script can be downloaded and run independently to create new Symfony projects.
# It clones the template repository and runs the full setup process.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ThyreenAgain/symfony-docker-thy/main/install.sh | bash
#
# Or download and run:
#   wget https://raw.githubusercontent.com/ThyreenAgain/symfony-docker-thy/main/install.sh
#   chmod +x install.sh
#   ./install.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Symfony Docker Template - Project Installer             ║${NC}"
echo -e "${BLUE}║     https://github.com/ThyreenAgain/symfony-docker-thy      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check dependencies
echo "Checking dependencies..."
for cmd in git docker; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}ERROR: '$cmd' is required but not installed.${NC}"
        exit 1
    fi
done

# Check Docker Compose
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}ERROR: Docker Compose is required but not found.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All dependencies found${NC}"
echo ""

# Clone template repository to temporary location
TEMP_DIR=$(mktemp -d)
REPO_URL="https://github.com/ThyreenAgain/symfony-docker-thy"

echo "Downloading Symfony Docker Template..."
git clone --depth 1 --quiet "$REPO_URL" "$TEMP_DIR"

if [ ! -f "$TEMP_DIR/setup/setup.sh" ]; then
    echo -e "${RED}ERROR: Setup script not found in repository.${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${GREEN}✓ Template downloaded${NC}"
echo ""

# Make setup script executable
chmod +x "$TEMP_DIR/setup/setup.sh"
chmod +x "$TEMP_DIR/setup/setup2.sh"

# Run the full setup process
cd "$TEMP_DIR"
./setup/setup.sh

# Cleanup temporary directory
cd ..
rm -rf "$TEMP_DIR"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Installation Complete!                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"