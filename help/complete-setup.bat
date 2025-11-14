@echo off
echo ========================================
echo Synapse App - Complete Setup with SSL
echo ========================================
echo.
echo This will:
echo 1. Build and start all containers
echo 2. Install SSL certificate automatically
echo 3. Open your browser to the app
echo.

echo Step 1: Making sure containers are clean...
docker compose -f compose.yaml -f compose.override.yaml -f compose.mercure.yaml down --remove-orphans

echo.
echo Step 2: Using Makefile to start with SSL certificate...
bash -c "make up-with-cert"

echo.
echo Step 3: Waiting for containers to be ready...
timeout /t 5 /nobreak >nul

echo.
echo Step 4: Checking container status...
docker compose -f compose.yaml -f compose.override.yaml -f compose.mercure.yaml ps

echo.
echo Step 5: Starting browser...
start http://localhost:80
timeout /t 2 /nobreak >nul
start https://localhost:443

echo.
echo ========================================
echo Setup Complete!
echo ========================================
echo.
echo Your application is now running at:
echo - HTTP:  http://localhost:80
echo - HTTPS: https://localhost:443
echo.
echo The SSL certificate has been automatically installed.
echo If you still see warnings, try refreshing the browser.
echo.
echo To stop: make down
echo To view logs: make logs
echo ========================================
pause