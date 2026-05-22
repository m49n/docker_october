# syntax=docker/dockerfile:1.7

FROM php:8.4-fpm-bookworm AS app

WORKDIR /var/www/html

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/tmp/composer

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libonig-dev \
        libpng-dev \
        libpq-dev \
        librdkafka-dev \
        libxml2-dev \
        libzip-dev \
        procps \
        unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath \
        curl \
        exif \
        gd \
        intl \
        mbstring \
        opcache \
        pcntl \
        pdo \
        pdo_pgsql \
        pgsql \
        soap \
        xml \
        zip \
    && pecl install redis rdkafka \
    && docker-php-ext-enable redis rdkafka \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY docker/php/php.ini /usr/local/etc/php/conf.d/99-october-production.ini
COPY docker/php/opcache.ini /usr/local/etc/php/conf.d/10-opcache.ini
COPY docker/php/www.conf /usr/local/etc/php-fpm.d/www.conf

COPY composer.json composer.lock ./

RUN --mount=type=cache,target=/tmp/composer-cache \
    --mount=type=secret,id=composer_auth,required=false \
    set -eux; \
    if [ -f /run/secrets/composer_auth ]; then \
        mkdir -p "$COMPOSER_HOME"; \
        cp /run/secrets/composer_auth "$COMPOSER_HOME/auth.json"; \
    fi; \
    COMPOSER_CACHE_DIR=/tmp/composer-cache composer install \
        --no-dev \
        --prefer-dist \
        --no-interaction \
        --no-progress \
        --optimize-autoloader \
        --no-scripts; \
    rm -f "$COMPOSER_HOME/auth.json"

COPY --chown=www-data:www-data . .

RUN set -eux; \
    composer dump-autoload --no-dev --optimize; \
    mkdir -p \
        bootstrap/cache \
        storage/app \
        storage/cms/cache \
        storage/cms/combiner \
        storage/cms/twig \
        storage/framework/cache \
        storage/framework/cache/data \
        storage/framework/sessions \
        storage/framework/views \
        storage/logs; \
    chown -R www-data:www-data bootstrap/cache storage

USER www-data

CMD ["php-fpm"]

FROM nginx:1.27-alpine AS nginx

WORKDIR /var/www/html

COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=app /var/www/html /var/www/html
