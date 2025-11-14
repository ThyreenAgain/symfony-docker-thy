#!/bin/bash

echo "========================================="
echo "Daily Development Commands (After Cert Setup)"
echo "========================================="
echo
echo "START WORKFLOW:"
echo "  make up              # Start containers (cert already installed)"
echo
echo "DURING DEVELOPMENT:"
echo "  make logs            # Watch live logs"
echo "  make sh              # Debug in container"
echo "  make sf c='...'      # Run Symfony commands"
echo "  make composer c='...' # Run Composer commands"
echo
echo "END WORKDAY:"
echo "  make down            # Stop containers"
echo
echo "REBUILD IF NEEDED:"
echo "  make build           # Rebuild images (cert still valid)"
echo "  make up              # Restart (cert still installed)"
echo
echo "========================================="
echo "Certificate: Installed ONCE, use FOREVER!"
echo "========================================="