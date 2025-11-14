#!/bin/bash

echo "=== Environment File Loading Debug Script ==="
echo

echo "1. Checking which .env files exist in the project root:"
echo "   Current directory: $(pwd)"
echo

for env_file in .env .env.local .env.dev .env.dev.local; do
    if [ -f "$env_file" ]; then
        echo "✓ Found: $env_file"
        echo "  Size: $(wc -l < "$env_file") lines"
        echo "  Permissions: $(ls -la "$env_file" | awk '{print $1, $3, $4}')"
        echo "  Last modified: $(ls -la "$env_file" | awk '{print $6, $7, $8}')"
        echo
    else
        echo "✗ Missing: $env_file"
    fi
done

echo "2. Docker Compose environment file loading:"
echo "   Docker Compose loads .env files in this order:"
echo "   - .env (project directory)"
echo "   - Environment variables from docker compose command (-f flags)"
echo "   - Docker Compose explicitly specified env files"
echo

echo "3. Symfony Environment File Loading Priority:"
echo "   Symfony loads .env files in this order (later overrides earlier):"
echo "   a) .env (base configuration)"
echo "   b) .env.local (machine-specific, not in git)"
echo "   c) .env.dev (development specific)"
echo "   d) .env.dev.local (local development overrides, highest priority)"
echo

echo "4. Current Docker Compose environment variables:"
echo "   Checking if docker-compose is available..."
if command -v docker-compose &> /dev/null || command -v docker &> /dev/null; then
    echo "   Docker Compose found. To see loaded variables, run:"
    echo "   docker compose config"
    echo "   or"
    echo "   docker compose -f compose.yaml -f compose.override.yaml -f compose.mercure.yaml config"
else
    echo "   Docker Compose not found in PATH"
fi

echo
echo "5. To debug Symfony environment loading at runtime:"
echo "   Add this to a controller or command:"
echo "   dump(\$_ENV); // Shows all environment variables"
echo "   dump(getenv()); // Shows environment variables"
echo "   dump(\$_SERVER); // Shows server variables"
echo
echo "6. Quick check - merge all .env files and show merged result:"
if [ -f .env.dev.local ]; then
    echo "   Priority 4 (highest): .env.dev.local"
    cat .env.dev.local
    echo
fi
if [ -f .env.dev ]; then
    echo "   Priority 3: .env.dev"
    cat .env.dev
    echo
fi
if [ -f .env.local ]; then
    echo "   Priority 2: .env.local"
    cat .env.local
    echo
fi
if [ -f .env ]; then
    echo "   Priority 1 (lowest): .env"
    cat .env
fi