#!/usr/bin/env sh
set -eu

: "${DEPLOY_HOST:?DEPLOY_HOST is required}"
: "${DEPLOY_USER:?DEPLOY_USER is required}"
: "${DEPLOY_PATH:?DEPLOY_PATH is required}"

DEPLOY_PORT="${DEPLOY_PORT:-22}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
DEPLOY_USE_LOCAL_DB="${DEPLOY_USE_LOCAL_DB:-1}"
DEPLOY_RUN_LARAVEL_MIGRATIONS="${DEPLOY_RUN_LARAVEL_MIGRATIONS:-0}"
DEPLOY_RUN_OPTIMIZE="${DEPLOY_RUN_OPTIMIZE:-0}"
DEPLOY_STRICT_HOST_KEY_CHECKING="${DEPLOY_STRICT_HOST_KEY_CHECKING:-accept-new}"
DEPLOY_COMPOSE_FILE="${DEPLOY_COMPOSE_FILE:-docker-compose.prod.yml}"
DEPLOY_BUILD_SECRET_FILE="${DEPLOY_BUILD_SECRET_FILE:-auth.json}"

PROJECT_NAME="${BITBUCKET_REPO_FULL_NAME:-${CI_PROJECT_NAME:-october-project}}"
COMMIT_SHA="${BITBUCKET_COMMIT:-${CI_COMMIT_SHA:-unknown}}"
BRANCH_NAME="${BITBUCKET_BRANCH:-${DEPLOY_BRANCH}}"

notify() {
    if [ -x scripts/telegram-notify.sh ]; then
        scripts/telegram-notify.sh "$1" || true
    fi
}

cleanup_key() {
    if [ -n "${tmp_key:-}" ] && [ -f "$tmp_key" ]; then
        rm -f "$tmp_key"
    fi
}
trap cleanup_key EXIT INT TERM

ssh_dir="$HOME/.ssh"
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"

ssh_opts="-p ${DEPLOY_PORT} -o BatchMode=yes -o StrictHostKeyChecking=${DEPLOY_STRICT_HOST_KEY_CHECKING}"

if [ -n "${DEPLOY_KNOWN_HOSTS:-}" ]; then
    printf '%s\n' "$DEPLOY_KNOWN_HOSTS" > "$ssh_dir/known_hosts"
    chmod 600 "$ssh_dir/known_hosts"
    ssh_opts="$ssh_opts -o UserKnownHostsFile=$ssh_dir/known_hosts"
fi

if [ -n "${DEPLOY_SSH_PRIVATE_KEY:-}" ]; then
    tmp_key="$ssh_dir/deploy_key"
    printf '%s\n' "$DEPLOY_SSH_PRIVATE_KEY" > "$tmp_key"
    chmod 600 "$tmp_key"
    ssh_opts="$ssh_opts -i $tmp_key"
fi

shell_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

remote_env="
export DEPLOY_PATH=$(shell_quote "$DEPLOY_PATH")
export DEPLOY_BRANCH=$(shell_quote "$DEPLOY_BRANCH")
export DEPLOY_USE_LOCAL_DB=$(shell_quote "$DEPLOY_USE_LOCAL_DB")
export DEPLOY_RUN_LARAVEL_MIGRATIONS=$(shell_quote "$DEPLOY_RUN_LARAVEL_MIGRATIONS")
export DEPLOY_RUN_OPTIMIZE=$(shell_quote "$DEPLOY_RUN_OPTIMIZE")
export DEPLOY_COMPOSE_FILE=$(shell_quote "$DEPLOY_COMPOSE_FILE")
export DEPLOY_BUILD_SECRET_FILE=$(shell_quote "$DEPLOY_BUILD_SECRET_FILE")
"

remote_script='
set -eu
cd "$DEPLOY_PATH"

git fetch --prune origin
git checkout "$DEPLOY_BRANCH"
git pull --ff-only origin "$DEPLOY_BRANCH"

IMAGE_TAG="$(git rev-parse --short HEAD)"
APP_IMAGE_VALUE="$(grep -E "^APP_IMAGE=" .env | cut -d= -f2- || true)"
NGINX_IMAGE_VALUE="$(grep -E "^NGINX_IMAGE=" .env | cut -d= -f2- || true)"
APP_IMAGE_VALUE="${APP_IMAGE_VALUE:-october-app}"
NGINX_IMAGE_VALUE="${NGINX_IMAGE_VALUE:-october-nginx}"

if [ -f "$DEPLOY_BUILD_SECRET_FILE" ]; then
    DOCKER_BUILDKIT=1 docker build --secret "id=composer_auth,src=$DEPLOY_BUILD_SECRET_FILE" --target app -t "$APP_IMAGE_VALUE:$IMAGE_TAG" .
else
    DOCKER_BUILDKIT=1 docker build --target app -t "$APP_IMAGE_VALUE:$IMAGE_TAG" .
fi

DOCKER_BUILDKIT=1 docker build --target nginx -t "$NGINX_IMAGE_VALUE:$IMAGE_TAG" .

if grep -q "^IMAGE_TAG=" .env; then
    sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=$IMAGE_TAG/" .env
else
    printf "\nIMAGE_TAG=%s\n" "$IMAGE_TAG" >> .env
fi

chmod +x scripts/deploy.sh
COMPOSE_FILE="$DEPLOY_COMPOSE_FILE" \
DEPLOY_PULL=0 \
USE_LOCAL_DB="$DEPLOY_USE_LOCAL_DB" \
RUN_LARAVEL_MIGRATIONS="$DEPLOY_RUN_LARAVEL_MIGRATIONS" \
RUN_OPTIMIZE="$DEPLOY_RUN_OPTIMIZE" \
./scripts/deploy.sh
'

notify "[deploy:start] ${PROJECT_NAME} ${BRANCH_NAME} ${COMMIT_SHA} -> ${DEPLOY_HOST}"

if ssh $ssh_opts "${DEPLOY_USER}@${DEPLOY_HOST}" "$remote_env sh -s" <<EOF
$remote_script
EOF
then
    notify "[deploy:success] ${PROJECT_NAME} ${BRANCH_NAME} ${COMMIT_SHA} -> ${DEPLOY_HOST}"
else
    status=$?
    notify "[deploy:failure] ${PROJECT_NAME} ${BRANCH_NAME} ${COMMIT_SHA} -> ${DEPLOY_HOST} exit=${status}"
    exit "$status"
fi
