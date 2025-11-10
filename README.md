# Symfony Docker - Modular Template

A [Docker](https://www.docker.com/)-based installer and runtime for the [Symfony](https://symfony.com) web framework,
with [FrankenPHP](https://frankenphp.dev) and [Caddy](https://caddyserver.com/) inside!

**Enhanced with:**
- **Modular Optional Features** - Choose only what you need (Mailer, Mercure)
- **Automated Setup** - One-command project creation
- **COMPOSE_PROJECT_NAME** - Proper Docker resource namespacing
- **Multiple Projects** - Run several projects simultaneously without conflicts

## Requirements

- **Docker** 20.10+
- **Docker Compose** 2.10+
- **Git** (for installation)
- **Bash** shell (Linux/macOS native, or WSL2 on Windows)

### ⚠️ Important for Windows Users

**The setup scripts MUST be run from a Bash shell.** Windows Command Prompt and PowerShell are **NOT compatible**.

**Recommended Setup for Windows:**
1. Install [WSL2 (Windows Subsystem for Linux)](https://learn.microsoft.com/en-us/windows/wsl/install)
2. Install Docker Desktop with WSL2 integration enabled
3. Run the setup scripts from within your WSL2 Ubuntu terminal

**Known Issue - WSL Port Detection:**
When running from WSL with Docker Desktop on Windows, the setup script may not detect that ports (like 3306) are already in use by Windows applications. This is because WSL network tools cannot see Windows host ports.

**Workaround:**
- The enhanced port detection will now check both WSL and Windows ports
- If you see warnings about ports, choose different ports during setup
- Or stop the Windows service using the port before running setup

## Quick Start (Recommended)

### One-Command Installation

**On Linux/macOS:**
```bash
# Download and run the installer
curl -fsSL https://raw.githubusercontent.com/ThyreenAgain/symfony-docker-thy/main/install.sh | bash
```

**On Windows (WSL2):**
```bash
# First, open WSL2 terminal (Ubuntu)
# Then run:
curl -fsSL https://raw.githubusercontent.com/ThyreenAgain/symfony-docker-thy/main/install.sh | bash
```

Or download first:

```bash
wget https://raw.githubusercontent.com/ThyreenAgain/symfony-docker-thy/main/install.sh
chmod +x install.sh
./install.sh
```

The installer will:
1. ✅ Check dependencies (Docker, Git)
2. ✅ Clone the template
3. ✅ Ask about optional features (Mailer, Mercure)
4. ✅ Configure your project
5. ✅ Build and start containers
6. ✅ Your app is ready!

## Manual Setup (For Development)

If you want to clone and customize the template:

**Linux/macOS or WSL2:**
```bash
# 1. Clone this repository
git clone https://github.com/ThyreenAgain/symfony-docker-thy.git
cd symfony-docker-thy

# 2. Run the setup script (MUST use bash)
cd setup
chmod +x setup.sh
./setup.sh

# 3. Follow the prompts
#    - Project name
#    - Database credentials
#    - Optional features (Mailer, Mercure)
#    - Port configuration
```

**⚠️ Windows Note:** Do NOT run setup scripts from Windows Command Prompt or PowerShell. Use WSL2 terminal.

## Features

### Core Features
- ✅ **Production, development and CI ready**
- ✅ **MySQL database** included by default
- ✅ **Blazing-fast performance** with [FrankenPHP worker mode](https://frankenphp.dev/docs/worker/)
- ✅ **Automatic HTTPS** in development and production
- ✅ **HTTP/3** and [Early Hints](https://symfony.com/blog/new-in-symfony-6-3-early-hints) support
- ✅ **Native XDebug integration** for debugging
- ✅ **Makefile shortcuts** for common tasks

### Optional Features (Choose During Setup)

#### 📧 Mailer (Mailpit)
- Email testing service with web UI
- Catches all emails in development
- View emails at `http://localhost:8025`
- **When to enable:** Your app sends emails

#### ⚡ Mercure Hub
- Real-time messaging (Server-Sent Events)
- Live updates without polling
- Built into FrankenPHP
- **When to enable:** Chat, notifications, real-time dashboards

## What Makes This Special

### 🎯 Modular Architecture
Choose only the features you need:
- Minimal setup: Just PHP + Database
- Standard setup: + Mailpit for emails
- Full setup: + Mercure for real-time features

### 🔧 COMPOSE_PROJECT_NAME
Uses Docker's official way to namespace projects:
- Run multiple projects simultaneously
- No manual prefix configuration
- Clean, predictable container names

### 📝 Official Makefile Pattern
Follows [symfony-docker best practices](https://github.com/dunglas/symfony-docker/blob/main/docs/makefile.md):
```bash
make help    # Show all commands
make up      # Start services
make down    # Stop services
make logs    # View logs
make sh      # Access PHP container
make sf c=about  # Run Symfony commands
```
## Architecture Overview
Repository Root
├── install.sh              ← NEW! Standalone bootstrap
│   └── Downloads template to /tmp
│       └── Runs setup.sh
│           └── Creates new project
│
└── setup/
    ├── setup.sh            ← Main setup wizard
    │   └── Clones template to project directory
    │       └── Calls setup2.sh
    │
    └── setup2.sh           ← Configuration & build
        └── Configures project
            └── Starts containers

## Project Structure

```
symfony-docker-thy/
├── install.sh              # Standalone installer (run this!)
├── setup/
│   ├── setup.sh           # Interactive setup wizard
│   └── setup2.sh          # Configuration and build script
├── compose.yaml           # Core services (PHP, Database)
├── compose.override.yaml  # Development overrides
├── compose.mailer.yaml    # Optional: Mailpit service
├── compose.mercure.yaml   # Optional: Mercure configuration
├── Dockerfile             # Multi-stage PHP/FrankenPHP build
├── Makefile              # Convenient command shortcuts
└── docs/
    ├── OPTIONAL_FEATURES.md  # Guide to modular features
    └── UPGRADE_NOTES.md      # Migration from previous versions
```

## Usage Examples

### Starting Your Project

```bash
# Using Makefile (recommended)
make up
make logs

# Using docker compose directly
docker compose up -d
docker compose logs -f
```

### Accessing Services

- **Application:** https://localhost
- **Mailpit UI:** http://localhost:8025 (if enabled)
- **Database:** localhost:3306 (configurable)

### Common Commands

```bash
# Access PHP container
make sh

# Run Symfony commands
make sf c="cache:clear"
make sf c="debug:router"

# Database operations
make migrate            # Run migrations
make db-reset          # Reset database

# Install dependencies
make install           # Composer + Yarn

# Build assets
make assets            # Run yarn build

# Run tests
make test
```

## Multiple Projects

Thanks to `COMPOSE_PROJECT_NAME`, running multiple projects is easy:

```bash
# Project 1 (ports: 80, 443, 3306)
cd project1
make up

# Project 2 (different ports: 8080, 8443, 3307)
cd project2
# During setup, choose different ports
make up

# Both run simultaneously without conflicts!
```

## Documentation

- 📘 [Optional Features Guide](OPTIONAL_FEATURES.md) - Detailed guide to Mailer and Mercure
- 📗 [Upgrade Notes](UPGRADE_NOTES.md) - Migration from previous versions
- 📙 [Using MySQL](docs/mysql.md) - MySQL configuration (included by default)
- 📕 [Debugging with Xdebug](docs/xdebug.md) - XDebug setup
- 📔 [Deploying in Production](docs/production.md) - Production deployment guide
- 📓 [TLS Certificates](docs/tls.md) - HTTPS configuration
- 📒 [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

## Advantages Over Official symfony-docker

✅ **Automated setup** - One command to working project  
✅ **MySQL by default** - Most projects use MySQL  
✅ **Optional features** - Choose what you need  
✅ **Better namespacing** - Uses COMPOSE_PROJECT_NAME  
✅ **Multiple projects** - Easy to run several simultaneously  
✅ **Comprehensive docs** - Detailed guides included  
✅ **Node.js included** - For Webpack Encore  
✅ **Python tools** - For Spec Kit CLI  

## Troubleshooting

### Windows: Setup Script Not Working

**Problem:** Getting errors when running setup from Windows Command Prompt or PowerShell.

**Solution:**
```bash
# ❌ DON'T use Command Prompt or PowerShell
C:\> .\setup\setup.sh  # This will FAIL

# ✅ DO use WSL2
$ ./setup/setup.sh     # This works
```

The scripts require Bash and Linux utilities. Use WSL2 on Windows.

### WSL: Port Detection Not Working

**Problem:** Setup doesn't detect that port 3306 (or others) is already in use by Docker Desktop on Windows.

**Root Cause:** WSL network tools (lsof, netstat, ss) cannot see Windows host ports.

**Solution:** The updated script now checks Windows ports via PowerShell. You'll see detailed diagnostic output like:
```
🐧 WSL Environment Detected - Checking both WSL and Windows ports...
   📊 Using 'lsof' for WSL port detection...
   ✓ Port 3306 is available in WSL (lsof check)
   🪟 Checking Windows host ports via PowerShell...
   ⚠ Port 3306 is in use on Windows host!
```

**Workaround if detection still fails:**
1. Stop Docker Desktop before running setup
2. Or choose different ports during setup (e.g., 3307 for MySQL)
3. Or run the setup script from Windows PowerShell (not recommended - use WSL2)

### Port Already in Use

```bash
# Check what's using the port in Docker
docker ps

# On Windows, check Windows services
Get-NetTCPConnection -LocalPort 3306

# Choose different ports during setup
# Or stop the conflicting service
docker stop <container-id>
```

### Permission Denied on Setup Script

```bash
chmod +x install.sh
# or
chmod +x setup/setup.sh setup/setup2.sh
```

### Can't Access https://localhost

```bash
# Check containers are running
docker compose ps

# Check logs for errors
docker compose logs php

# Restart services
docker compose down
docker compose up -d
```

## Contributing

This is a customized fork of [dunglas/symfony-docker](https://github.com/dunglas/symfony-docker) with additional features and automation.

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is available under the MIT License.

## Credits

- Base template by [Kévin Dunglas](https://dunglas.dev)
- Enhanced and maintained by [Thyreen](https://github.com/ThyreenAgain)
- Inspired by the Symfony community's feedback and needs
