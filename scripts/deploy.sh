#!/usr/bin/env sh
set -eu

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
USE_LOCAL_DB="${USE_LOCAL_DB:-0}"
DEPLOY_PULL="${DEPLOY_PULL:-1}"
RUN_LARAVEL_MIGRATIONS="${RUN_LARAVEL_MIGRATIONS:-0}"
RUN_OPTIMIZE="${RUN_OPTIMIZE:-0}"

compose() {
    if [ "$USE_LOCAL_DB" = "1" ]; then
        docker compose -f "$COMPOSE_FILE" --profile local-db "$@"
    else
        docker compose -f "$COMPOSE_FILE" "$@"
    fi
}

if [ "$DEPLOY_PULL" = "1" ]; then
    compose pull
fi

if [ "$USE_LOCAL_DB" = "1" ]; then
    compose up -d redis postgres
else
    compose up -d redis
fi

compose run --rm php-fpm php artisan october:migrate --force

if [ "$RUN_LARAVEL_MIGRATIONS" = "1" ]; then
    compose run --rm php-fpm php artisan migrate --force
fi

if [ "$RUN_OPTIMIZE" = "1" ]; then
    compose run --rm php-fpm php artisan optimize
fi

compose run --rm php-fpm php artisan queue:restart || true
compose run --rm php-fpm php artisan schedule:interrupt || true
compose up -d --remove-orphans
compose ps
