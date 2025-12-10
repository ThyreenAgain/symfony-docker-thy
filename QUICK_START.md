# Quick Start Guide

## Database Configuration

This template supports multiple database types. The database type is controlled by the `DB_TYPE` variable in your `.env` file.

### Setting Your Database Type

1. Open the `.env` file in your project root
2. Set the `DB_TYPE` variable to one of these values:
   - `mysql` - MySQL database (default)
   - `postgres` - PostgreSQL database
   - `postgis` - PostgreSQL with PostGIS spatial extensions
   - `none` - No database (API-only projects)

### Example: Switching to PostgreSQL

**Step 1:** Edit `.env`
```bash
# Change this line:
DB_TYPE=mysql

# To this:
DB_TYPE=postgres
```

**Step 2:** Update database credentials in `.env`
```bash
# Comment out MySQL config:
# MYSQL_VERSION=8
# MYSQL_DATABASE=app
# MYSQL_USER=app
# MYSQL_PASSWORD=!ChangeMe!
# MYSQL_ROOT_PASSWORD=!ChangeMe!
# MYSQL_CHARSET=utf8mb4
# DB_HOST_PORT=3306

# Uncomment PostgreSQL config:
POSTGRES_DB=app
POSTGRES_USER=app
POSTGRES_PASSWORD=!ChangeMe!
DB_HOST_PORT=5432
```

**Step 3:** Update `.env.dev.local` with matching credentials
```bash
DB_TYPE=postgres
POSTGRES_DB=app
POSTGRES_USER=app
POSTGRES_PASSWORD=!ChangeMe!

# Set the DATABASE_URL
DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@database:5432/${POSTGRES_DB}?serverVersion=18&charset=utf8
```

**Step 4:** Restart containers
```bash
make down
make up
```

## How It Works

The `DB_TYPE` variable controls which Docker Compose file is included:
- `DB_TYPE=mysql` → includes `compose.mysql.yaml`
- `DB_TYPE=postgres` → includes `compose.postgres.yaml`
- `DB_TYPE=postgis` → includes `compose.postgis.yaml`
- `DB_TYPE=none` → no database compose file

The Makefile automatically detects `DB_TYPE` from `.env` and includes the appropriate compose file.

## Common Commands

```bash
make help       # Show all available commands
make up         # Start containers
make down       # Stop containers
make logs       # View logs
make bash       # Connect to PHP container
make sf c=about # Run Symfony console commands
```

## Need Help?

- Check the [Makefile](Makefile) for all available commands
- See [docs/](docs/) for detailed documentation
- Visit https://github.com/ThyreenAgain/symfony-docker-thy