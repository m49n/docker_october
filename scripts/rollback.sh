#!/usr/bin/env sh
set -eu

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
USE_LOCAL_DB="${USE_LOCAL_DB:-0}"
DEPLOY_PULL="${DEPLOY_PULL:-0}"
ROLLBACK_WAIT_SECONDS="${ROLLBACK_WAIT_SECONDS:-90}"
ROLLBACK_WAIT_INTERVAL="${ROLLBACK_WAIT_INTERVAL:-3}"

TARGET_TAG="${1:-${ROLLBACK_IMAGE_TAG:-}}"

usage() {
    cat >&2 <<'USAGE'
Usage:
  ./scripts/rollback.sh <image-tag>
  ROLLBACK_IMAGE_TAG=<image-tag> ./scripts/rollback.sh

Environment:
  COMPOSE_FILE=docker-compose.prod.yml
  USE_LOCAL_DB=1
  DEPLOY_PULL=0
  ROLLBACK_WAIT_SECONDS=90
USAGE
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

if [ -z "$TARGET_TAG" ]; then
    usage
    exit 2
fi

if [ ! -f .env ]; then
    error ".env was not found. Run rollback from the project root."
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    error "$COMPOSE_FILE was not found. Run rollback from the project root."
fi

get_env_value() {
    key="$1"
    grep -E "^${key}=" .env | tail -n 1 | cut -d= -f2- || true
}

set_env_value() {
    key="$1"
    value="$2"
    tmp_file=".env.rollback.$$"

    awk -v key="$key" -v value="$value" '
        BEGIN { found = 0 }
        index($0, key "=") == 1 {
            print key "=" value
            found = 1
            next
        }
        { print }
        END {
            if (found == 0) {
                print key "=" value
            }
        }
    ' .env > "$tmp_file"

    cat "$tmp_file" > .env
    rm -f "$tmp_file"
}

compose() {
    if [ "$USE_LOCAL_DB" = "1" ]; then
        docker compose -f "$COMPOSE_FILE" --profile local-db "$@"
    else
        docker compose -f "$COMPOSE_FILE" "$@"
    fi
}

wait_for_service() {
    service="$1"
    elapsed=0

    while [ "$elapsed" -le "$ROLLBACK_WAIT_SECONDS" ]; do
        container_id="$(compose ps -q "$service" 2>/dev/null || true)"
        if [ -n "$container_id" ]; then
            status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id" 2>/dev/null || true)"
            case "$status" in
                healthy|running)
                    echo "$service is $status"
                    return 0
                    ;;
                unhealthy|exited|dead)
                    error "$service is $status after rollback"
                    ;;
            esac
        fi

        sleep "$ROLLBACK_WAIT_INTERVAL"
        elapsed=$((elapsed + ROLLBACK_WAIT_INTERVAL))
    done

    error "$service did not become healthy within ${ROLLBACK_WAIT_SECONDS}s"
}

current_tag="$(get_env_value IMAGE_TAG)"
app_image="$(get_env_value APP_IMAGE)"
nginx_image="$(get_env_value NGINX_IMAGE)"
app_image="${app_image:-october-app}"
nginx_image="${nginx_image:-october-nginx}"

echo "Rolling back IMAGE_TAG from ${current_tag:-<unset>} to $TARGET_TAG"

if [ "$DEPLOY_PULL" = "1" ]; then
    IMAGE_TAG="$TARGET_TAG" compose pull
else
    docker image inspect "$app_image:$TARGET_TAG" >/dev/null || error "Missing local image: $app_image:$TARGET_TAG"
    docker image inspect "$nginx_image:$TARGET_TAG" >/dev/null || error "Missing local image: $nginx_image:$TARGET_TAG"
fi

set_env_value IMAGE_TAG "$TARGET_TAG"
compose up -d --remove-orphans
wait_for_service php-fpm
wait_for_service nginx
compose ps

echo "Rollback complete: $TARGET_TAG"
