#!/bin/bash
#
# Safe Project Move Script
# This script moves the project from /tmp to your desired location
# WITHOUT requiring sudo
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Safe Project Move Script ===${NC}"
echo ""

# Get current project location (where this script is located)
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME=$(basename "$CURRENT_DIR")

# Default destination is parent directory
DESTINATION="${1:-$CURRENT_DIR/../$PROJECT_NAME}"

echo "Current project location: $CURRENT_DIR"
echo "Destination: $DESTINATION"
echo ""

# Check if destination exists
if [ -d "$DESTINATION" ]; then
    echo -e "${RED}ERROR: Destination directory already exists!${NC}"
    echo "Please choose a different destination or remove the existing directory."
    exit 1
fi

# Check if destination parent directory exists and is writable
DEST_PARENT=$(dirname "$DESTINATION")
if [ ! -d "$DEST_PARENT" ]; then
    echo -e "${RED}ERROR: Parent directory '$DEST_PARENT' does not exist.${NC}"
    exit 1
fi

# Check write permissions
if [ ! -w "$DEST_PARENT" ]; then
    echo -e "${RED}ERROR: No write permission for directory '$DEST_PARENT'.${NC}"
    echo ""
    echo "Solutions:"
    echo "1. Choose a different destination in a writable location"
    echo "2. Run with appropriate permissions: cp -r $CURRENT_DIR $DESTINATION"
    exit 1
fi

echo "✅ All checks passed!"
echo ""
echo "Moving project..."
echo "From: $CURRENT_DIR"
echo "To:   $DESTINATION"
echo ""

# Perform the move using cp instead of mv (more permissive)
if cp -r "$CURRENT_DIR" "$DESTINATION"; then
    echo ""
    echo -e "${GREEN}✅ Project moved successfully!${NC}"
    echo ""
    echo "New location: $DESTINATION"
    echo ""
    echo "Next steps:"
    echo "  cd $DESTINATION"
    echo "  make up"
    echo ""
    
    # Ask if user wants to remove the old location
    echo -n "Remove old temporary location? (y/N): "
    read -r remove_old
    
    if [[ "$remove_old" =~ ^[Yy]$ ]]; then
        echo "Removing old location..."
        rm -rf "$CURRENT_DIR"
        echo "✅ Old location removed."
    else
        echo "Old location preserved at: $CURRENT_DIR"
        echo "You can remove it manually if desired."
    fi
    
else
    echo -e "${RED}❌ Failed to copy project.${NC}"
    echo "You can manually copy with: cp -r $CURRENT_DIR $DESTINATION"
    exit 1
fi