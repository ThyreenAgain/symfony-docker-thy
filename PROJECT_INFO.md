# Project Information

## Created with Symfony Docker Installer

This project was created using the [Symfony Docker Template](https://github.com/ThyreenAgain/symfony-docker-thy) with automated setup.

## Quick Start

```bash
# Start the development environment
make up

# Access the application
open https://localhost

# View logs
make logs

# Access PHP container
make sh
```

## Services

- **Application:** https://localhost
- **Database:** localhost:3306 (configurable)
- **Mailpit:** http://localhost:8025 (if enabled)

## Available Commands

```bash
make help        # Show all commands
make up          # Start services
make down        # Stop services  
make logs        # View logs
make sh          # Access PHP container
make migrate     # Run database migrations
make assets      # Build frontend assets
```

## Full Documentation

For complete documentation, configuration options, and troubleshooting:
👉 **Visit: https://github.com/ThyreenAgain/symfony-docker-thy**

This includes:
- Detailed setup instructions
- Optional features (Mailer, Mercure)  
- Production deployment
- Troubleshooting guide
- MySQL configuration
- Xdebug setup

## Project Structure

```
├── compose.yaml              # Core services (PHP, Database)
├── compose.override.yaml     # Development overrides
├── Dockerfile                # PHP/FrankenPHP container
├── Makefile                  # Convenient commands
├── .env.dev.example          # Environment template
└── scripts/move-to.sh        # Helper for project relocation
## Moving Your Project

If you need to move this project to a different location:

**1. Stop containers:**
```bash
make down
```

**2. Move/copy to new location:**
```bash
cp -r . /your/new/location/project_name
# or
mv . /your/new/location/project_name
```

**3. Start from new location:**
```bash
cd /your/new/location/project_name
make up
```

Docker will automatically:
- Mount the new location to `/app` 
- Reuse existing database volume (data preserved)
- Start your app from the new location
```

## Support

If you encounter issues:
1. Check the full documentation: https://github.com/ThyreenAgain/symfony-docker-thy
2. Review troubleshooting section
3. Check Docker logs: `make logs`

---

**Template:** Symfony Docker Template* by Thyreen  
**Documentation:** https://github.com/ThyreenAgain/symfony-docker-thy
forked from https://github.com/dunglas/symfony-docker