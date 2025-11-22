# Executables (local)
DOCKER_COMP = docker compose

# Docker containers
PHP_CONT = $(DOCKER_COMP) exec php

# Executables
PHP      = $(PHP_CONT) php
COMPOSER = $(PHP_CONT) composer
SYMFONY  = $(PHP) bin/console

# Misc
.DEFAULT_GOAL = help
.PHONY        : help build up start down logs sh bash composer vendor sf cc test install-cert

## —— 🎵 🐳 The Symfony Docker Makefile 🐳 🎵 ——————————————————————————————————
help: ## Outputs this help screen
	@grep -E '(^[a-zA-Z0-9\./_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}{printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

## —— Docker 🐳 ————————————————————————————————————————————————————————————————
build: ## Builds the Docker images
	@$(DOCKER_COMP) build --pull --no-cache

up: ## Start the docker hub in detached mode (no logs)
	@$(DOCKER_COMP) -f compose.yaml -f compose.override.yaml -f compose.mercure.yaml up --detach

up-debug: ## Start the docker hub in detached mode (no logs)
	@$(DOCKER_COMP) -f compose.yaml -f compose.override.yaml -f compose.mercure.yaml up --wait&set XDEBUG_MODE=debug --detach 


start: build up ## Build and start the containers

down: ## Stop the docker hub
	@$(DOCKER_COMP) -f compose.yaml -f compose.override.yaml -f compose.mercure.yaml down --remove-orphans

logs: ## Show live logs
	@$(DOCKER_COMP) -f compose.yaml -f compose.override.yaml -f compose.mercure.yaml logs --tail=0 --follow

install-cert: ## Install Caddy certificate to system certificate store
	@echo "Detecting operating system and installing certificate..."
	@if command -v certutil >/dev/null 2>&1; then \
		echo "Installing certificate to Windows certificate store..."; \
		$(DOCKER_COMP) cp php:/data/caddy/pki/authorities/local/root.crt %TEMP%/root.crt && certutil -addstore -f "ROOT" %TEMP%/root.crt; \
	elif command -v update-ca-certificates >/dev/null 2>&1; then \
		echo "Installing certificate to Linux/Mac certificate store..."; \
		cp $$(docker compose ps -q php):/data/caddy/pki/authorities/local/root.crt /usr/local/share/ca-certificates/root.crt && sudo update-ca-certificates; \
	else \
		echo "Unable to detect certificate installation method for this system"; \
		echo "Please see the documentation for manual certificate installation"; \
	fi
	@echo "Certificate installation completed!"

up-with-cert: up install-cert ## Start containers and install certificate

sh: ## Connect to the PHP container
	@$(PHP_CONT) sh

bash: ## Connect to the PHP container via bash so up and down arrows go to previous commands
	@$(PHP_CONT) bash

test: ## Start tests with phpunit, pass the parameter "c=" to add options to phpunit, example: make test c="--group e2e --stop-on-failure"
	@$(eval c ?=)
	@$(DOCKER_COMP) exec -e APP_ENV=test php bin/phpunit $(c)

## —— Composer 🧙 ——————————————————————————————————————————————————————————————
composer: ## Run composer, pass the parameter "c=" to run a given command, example: make composer c='req symfony/orm-pack'
	@$(eval c ?=)
	@$(COMPOSER) $(c)

vendor: ## Install vendors according to the current composer.lock file
vendor: c=install --prefer-dist --no-dev --no-progress --no-scripts --no-interaction
vendor: composer

## —— Symfony 🎵 ———————————————————————————————————————————————————————————————
sf: ## List all Symfony commands or pass the parameter "c=" to run a given command, example: make sf c=about
	@$(eval c ?=)
	@$(SYMFONY) $(c)

cc: c=c:c ## Clear the cache
cc: sf

## —— Project 🚀 ———————————————————————————————————————————————————————————————
install: ## Install the project dependencies
	@$(COMPOSER) install --prefer-dist --no-progress --no-scripts --no-interaction
	@$(PHP_CONT) yarn install

migrate: ## Run database migrations
	@$(SYMFONY) doctrine:migrations:migrate --no-interaction

assets: ## Build frontend assets
	@$(PHP_CONT) yarn build

db-reset: ## Reset the database
	@$(SYMFONY) doctrine:database:drop --force --if-exists
	@$(SYMFONY) doctrine:database:create
	@$(SYMFONY) doctrine:migrations:migrate --no-interaction