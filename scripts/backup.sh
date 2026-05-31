#!/usr/bin/env sh
set -eu

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
USE_LOCAL_DB="${USE_LOCAL_DB:-1}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/october}"
BACKUP_TAG="${BACKUP_TAG:-$(date -u +%Y%m%dT%H%M%SZ)}"
BACKUP_POSTGRES="${BACKUP_POSTGRES:-1}"
BACKUP_STORAGE="${BACKUP_STORAGE:-1}"
BACKUP_METADATA="${BACKUP_METADATA:-1}"
BACKUP_INCLUDE_SECRETS="${BACKUP_INCLUDE_SECRETS:-0}"
STORAGE_VOLUME="${STORAGE_VOLUME:-october-production_storage-app}"

error() {
    echo "ERROR: $*" >&2
    exit 1
}

if [ ! -f .env ]; then
    error ".env was not found. Run backup from the project root."
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    error "$COMPOSE_FILE was not found. Run backup from the project root."
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

get_env_value() {
    key="$1"
    grep -E "^${key}=" .env | tail -n 1 | cut -d= -f2- || true
}

compose() {
    if [ "$USE_LOCAL_DB" = "1" ]; then
        docker compose -f "$COMPOSE_FILE" --profile local-db "$@"
    else
        docker compose -f "$COMPOSE_FILE" "$@"
    fi
}

postgres_db="$(get_env_value POSTGRES_DB)"
postgres_user="$(get_env_value POSTGRES_USER)"
postgres_db="${postgres_db:-october}"
postgres_user="${postgres_user:-october}"

echo "Starting backup: $BACKUP_TAG"
echo "Backup directory: $BACKUP_DIR"

if [ "$BACKUP_POSTGRES" = "1" ]; then
    postgres_file="$BACKUP_DIR/postgres-$BACKUP_TAG.dump"
    compose exec -T postgres \
        pg_dump -U "$postgres_user" -d "$postgres_db" --format=custom --no-owner --no-acl \
        > "$postgres_file"
    test -s "$postgres_file" || error "PostgreSQL backup is empty: $postgres_file"
    chmod 600 "$postgres_file"
    echo "PostgreSQL backup: $postgres_file"
fi

if [ "$BACKUP_STORAGE" = "1" ]; then
    storage_file="$BACKUP_DIR/storage-app-$BACKUP_TAG.tar.gz"
    docker run --rm \
        -v "$STORAGE_VOLUME:/data:ro" \
        -v "$BACKUP_DIR:/backup" \
        alpine:3.20 \
        tar -czf "/backup/storage-app-$BACKUP_TAG.tar.gz" -C /data .
    docker run --rm \
        -v "$BACKUP_DIR:/backup" \
        alpine:3.20 \
        chown "$(id -u):$(id -g)" "/backup/storage-app-$BACKUP_TAG.tar.gz"
    test -s "$storage_file" || error "Storage backup is empty: $storage_file"
    chmod 600 "$storage_file"
    echo "Storage backup: $storage_file"
fi

if [ "$BACKUP_METADATA" = "1" ]; then
    metadata_file="$BACKUP_DIR/metadata-$BACKUP_TAG.txt"
    {
        echo "date_utc=$BACKUP_TAG"
        echo "git_commit=$(git rev-parse HEAD 2>/dev/null || true)"
        echo "image_tag=$(get_env_value IMAGE_TAG)"
        echo "app_image=$(get_env_value APP_IMAGE)"
        echo "nginx_image=$(get_env_value NGINX_IMAGE)"
        echo
        compose ps
    } > "$metadata_file"
    chmod 600 "$metadata_file"
    echo "Metadata backup: $metadata_file"
fi

if [ "$BACKUP_INCLUDE_SECRETS" = "1" ]; then
    env_file="$BACKUP_DIR/env-$BACKUP_TAG"
    cp .env "$env_file"
    chmod 600 "$env_file"
    echo "Runtime env backup: $env_file"

    if [ -f auth.json ]; then
        auth_file="$BACKUP_DIR/auth-$BACKUP_TAG.json"
        cp auth.json "$auth_file"
        chmod 600 "$auth_file"
        echo "Composer auth backup: $auth_file"
    fi
fi

echo "Backup complete: $BACKUP_TAG"
