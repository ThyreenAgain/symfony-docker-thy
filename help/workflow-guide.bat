@echo off
echo ========================================
echo Development Workflow Guide
echo ========================================
echo.
echo FIRST TIME SETUP (one-time only):
echo   make up-with-cert    # Start + install cert
echo.
echo DAILY DEVELOPMENT (no cert needed):
echo   make up              # Start containers
echo   make logs            # View logs  
echo   make down            # Stop containers
echo   make build           # Rebuild if needed
echo.
echo SSL CERTIFICATE STATUS:
echo   - Installed to system cert store
echo   - Persistent across container restarts
echo   - No need to reinstall unless you:
echo     * Change systems
echo     * Reset certificate store
echo     * Use different dev machine
echo.
echo ========================================
echo Summary: Install cert ONCE, use forever!
echo ========================================
pause