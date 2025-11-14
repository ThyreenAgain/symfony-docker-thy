#syntax=docker/dockerfile:1

# Use a specific PHP 8.4 image as the base. You can change the version as needed.
FROM dunglas/frankenphp:1-php8.4 AS frankenphp_upstream

# The different stages of this Dockerfile are meant to be built into separate images
# https://docs.docker.com/develop/develop-images/multistage-build/#stop-at-a-specific-build-stage
# https://docs.docker.com/compose/compose-file/#target


# Base FrankenPHP image
FROM frankenphp_upstream AS frankenphp_base

WORKDIR /app

VOLUME /app/var/

# persistent / runtime deps
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
	file \
	git \
	&& rm -rf /var/lib/apt/lists/*

RUN set -eux; \
	install-php-extensions \
		@composer \
		apcu \
		intl \
		opcache \
		zip \
	;

	
# https://getcomposer.org/doc/03-cli.md#composer-allow-superuser
ENV COMPOSER_ALLOW_SUPERUSER=1

ENV PHP_INI_SCAN_DIR=":$PHP_INI_DIR/app.conf.d"

###> recipes ###
###< recipes ###

# Add Node.js and npm to the container (REQUIRED FOR SPEC KIT AND WEBPACK ENCORE)
# This uses the NodeSource repository for a reliable, up-to-date installation.
ARG NODE_VERSION=20 
RUN apt-get update \
    && apt-get install -y ca-certificates curl gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_VERSION.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && npm install -g yarn \
    && rm -rf /var/lib/apt/lists/*

# Add Spec Kit CLI tools (uv for package management, spec-cli)
# 4. Install Specify-CLI dependencies (Uses a Virtual Environment for PEP 668 compliance)
# Note: We still install python3-pip and python3-venv globally first.
RUN VENV_DIR=/opt/venv/specify-cli && \
    # 1. Install dependencies, create venv, and clean up apt cache
    apt-get update && apt-get install -y python3-pip python3-venv && \
    python3 -m venv ${VENV_DIR} && \
    rm -rf /var/lib/apt/lists/* && \
    \
    # 2. Use the venv's pip to install uv
    echo "Installing uv into virtual environment..." && \
    ${VENV_DIR}/bin/pip install --no-cache-dir uv && \
    \
    # 3. Use the venv's uv to install specify-cli
    echo "Installing specify-cli into virtual environment..." && \
    ${VENV_DIR}/bin/uv tool install specify-cli --from git+https://github.com/github/spec-kit.git && \
    \
    # 4. Create a symlink so the command is available system-wide
    echo "Creating system symlink for specify-cli..." && \
    ln -s ${VENV_DIR}/bin/specify-cli /usr/local/bin/specify-cli

COPY --link frankenphp/conf.d/10-app.ini $PHP_INI_DIR/app.conf.d/
COPY --link --chmod=755 frankenphp/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
COPY --link frankenphp/Caddyfile /etc/frankenphp/Caddyfile

ENTRYPOINT ["docker-entrypoint"]

###> doctrine/doctrine-bundle ###
#RUN install-php-extensions pdo_pgsql
RUN install-php-extensions pdo_mysql
###< doctrine/doctrine-bundle ###

HEALTHCHECK --start-period=60s CMD curl -f http://localhost:2019/metrics || exit 1
CMD [ "frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile" ]

# Dev FrankenPHP image
FROM frankenphp_base AS frankenphp_dev

ENV APP_ENV=dev
ENV XDEBUG_MODE=off
ENV FRANKENPHP_WORKER_CONFIG=watch

RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

RUN set -eux; \
	install-php-extensions \
		xdebug \
	;

COPY --link frankenphp/conf.d/20-app.dev.ini $PHP_INI_DIR/app.conf.d/

CMD [ "frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile", "--watch" ]

# Prod FrankenPHP image
FROM frankenphp_base AS frankenphp_prod

ENV APP_TINI_NO_REAPER=true
ENV APP_ENV=prod

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY --link frankenphp/conf.d/20-app.prod.ini $PHP_INI_DIR/app.conf.d/

# prevent the reinstallation of vendors at every changes in the source code
COPY --link composer.* symfony.* ./
RUN set -eux; \
	composer install --no-cache --prefer-dist --no-dev --no-autoloader --no-scripts --no-progress

# copy sources
COPY --link --exclude=frankenphp/ . ./

RUN set -eux; \
	mkdir -p var/cache var/log; \
	composer dump-autoload --classmap-authoritative --no-dev; \
	composer dump-env prod; \
	composer run-script --no-dev post-install-cmd; \
	chmod +x bin/console; sync;

# Uncomment this section if you use Symfony Encore to build CSS and JavaScript files
# (and add Node.js to the base image)
RUN set -eux; \
    npm install; \
    npm run build; \
    rm -rf node_modules;
