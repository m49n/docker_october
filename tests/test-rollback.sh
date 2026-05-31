#!/usr/bin/env sh
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    file="$1"
    pattern="$2"
    if ! grep -F "$pattern" "$file" >/dev/null 2>&1; then
        echo "Expected to find: $pattern" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        fail "missing expected pattern"
    fi
}

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

workspace="$tmp_dir/workspace"
bin_dir="$tmp_dir/bin"
mkdir -p "$workspace/scripts" "$bin_dir"

cp "$repo_root/scripts/rollback.sh" "$workspace/scripts/rollback.sh"
chmod +x "$workspace/scripts/rollback.sh"

cat > "$workspace/.env" <<'ENV'
APP_IMAGE=october-app
NGINX_IMAGE=october-nginx
IMAGE_TAG=current123
ENV

touch "$workspace/docker-compose.prod.yml"

cat > "$bin_dir/docker" <<'SH'
#!/usr/bin/env sh
set -eu
printf '%s\n' "docker $*" >> "$DOCKER_STUB_LOG"

if [ "$1" = "image" ] && [ "$2" = "inspect" ]; then
    case "$3" in
        october-app:old123|october-nginx:old123) exit 0 ;;
        *) exit 1 ;;
    esac
fi

if [ "$1" = "compose" ] && [ "$4" = "up" ]; then
    exit 0
fi

if [ "$1" = "compose" ] && [ "$4" = "ps" ] && [ "${5:-}" = "-q" ]; then
    printf '%s\n' "$6-id"
    exit 0
fi

if [ "$1" = "inspect" ] && [ "$2" = "-f" ]; then
    case "$4" in
        nginx-id|php-fpm-id) printf 'healthy\n' ;;
        *) printf 'running\n' ;;
    esac
    exit 0
fi

if [ "$1" = "compose" ] && [ "$4" = "ps" ]; then
    printf 'compose ps ok\n'
    exit 0
fi

exit 0
SH
chmod +x "$bin_dir/docker"

export DOCKER_STUB_LOG="$tmp_dir/docker.log"
export PATH="$bin_dir:$PATH"

cd "$workspace"

if ./scripts/rollback.sh >/tmp/rollback-no-arg.out 2>/tmp/rollback-no-arg.err; then
    fail "rollback without target tag should fail"
fi
assert_contains /tmp/rollback-no-arg.err "Usage:"

./scripts/rollback.sh old123 >/tmp/rollback.out

assert_contains .env "IMAGE_TAG=old123"
assert_contains "$DOCKER_STUB_LOG" "docker image inspect october-app:old123"
assert_contains "$DOCKER_STUB_LOG" "docker image inspect october-nginx:old123"
assert_contains "$DOCKER_STUB_LOG" "docker compose -f docker-compose.prod.yml up -d --remove-orphans"
assert_contains "$DOCKER_STUB_LOG" "docker compose -f docker-compose.prod.yml ps -q php-fpm"
assert_contains "$DOCKER_STUB_LOG" "docker compose -f docker-compose.prod.yml ps -q nginx"
assert_contains /tmp/rollback.out "Rollback complete: old123"

echo "rollback tests passed"
