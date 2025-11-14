#!/bin/bash

echo "========================================"
echo "Quick Make Commands Reference"
echo "========================================"
echo
echo "Docker Commands:"
echo "  make up              - Start containers"
echo "  make up-with-cert    - Start containers + install SSL cert (cross-platform)"
echo "  make install-cert    - Install SSL certificate only (Windows/Linux/Mac)"
echo "  make down            - Stop containers"
echo "  make logs            - Show live logs"
echo "  make build           - Rebuild containers"
echo
echo "SSL Certificate Installation:"
echo "  Windows:     Uses certutil command"
echo "  Linux/Mac:   Uses update-ca-certificates (sudo required)"
echo "  Cross-platform: Automatic OS detection in install-cert target"
echo
echo "Development:"
echo "  make sh              - Connect to PHP container"
echo "  make bash            - Connect to PHP container (bash)"
echo "  make composer c='...' - Run composer commands"
echo "  make sf c='...'      - Run Symfony console commands"
echo
echo "Database:"
echo "  make migrate         - Run database migrations"
echo "  make db-reset        - Reset database completely"
echo "  make vendor          - Install composer dependencies"
echo
echo "Utilities:"
echo "  make cc              - Clear Symfony cache"
echo "  make test            - Run tests"
echo "  make assets          - Build frontend assets"
echo "  make help            - Show this help"
echo
echo "========================================"
echo "Quick Start (Recommended for HTTPS):"
echo "  make up-with-cert"
echo "========================================"