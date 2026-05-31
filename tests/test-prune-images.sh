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

assert_not_contains() {
    file="$1"
    pattern="$2"
    if grep -F "$pattern" "$file" >/dev/null 2>&1; then
        echo "Did not expect to find: $pattern" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        fail "unexpected pattern"
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

cp "$repo_root/scripts/prune-images.sh" "$workspace/scripts/prune-images.sh"
chmod +x "$workspace/scripts/prune-images.sh"

cat > "$workspace/.env" <<'ENV'
APP_IMAGE=october-app
NGINX_IMAGE=october-nginx
IMAGE_TAG=keep-current
ENV

cat > "$bin_dir/docker" <<'SH'
#!/usr/bin/env sh
set -eu
printf '%s\n' "docker $*" >> "$DOCKER_STUB_LOG"

if [ "$1" = "image" ] && [ "$2" = "ls" ]; then
    case "$3" in
        october-app)
            printf '%s\n' \
                'october-app:keep-current' \
                'october-app:keep-new' \
                'october-app:delete-old' \
                'october-app:<none>'
            ;;
        october-nginx)
            printf '%s\n' \
                'october-nginx:keep-current' \
                'october-nginx:keep-new' \
                'october-nginx:delete-old'
            ;;
    esac
    exit 0
fi

if [ "$1" = "image" ] && [ "$2" = "rm" ]; then
    printf '%s\n' "removed $3" >> "$DOCKER_STUB_LOG"
    exit 0
fi

exit 0
SH
chmod +x "$bin_dir/docker"

export DOCKER_STUB_LOG="$tmp_dir/docker.log"
export PATH="$bin_dir:$PATH"

cd "$workspace"
IMAGE_KEEP_COUNT=2 IMAGE_PRUNE_DRY_RUN=1 ./scripts/prune-images.sh >/tmp/prune-dry.out
assert_contains /tmp/prune-dry.out "DRY RUN remove october-app:delete-old"
assert_contains /tmp/prune-dry.out "DRY RUN remove october-nginx:delete-old"
assert_not_contains "$DOCKER_STUB_LOG" "removed october-app:delete-old"

: > "$DOCKER_STUB_LOG"
IMAGE_KEEP_COUNT=2 IMAGE_PRUNE_DRY_RUN=0 ./scripts/prune-images.sh >/tmp/prune-delete.out
assert_contains "$DOCKER_STUB_LOG" "removed october-app:delete-old"
assert_contains "$DOCKER_STUB_LOG" "removed october-nginx:delete-old"
assert_not_contains "$DOCKER_STUB_LOG" "removed october-app:keep-current"
assert_not_contains "$DOCKER_STUB_LOG" "removed october-app:keep-new"
assert_not_contains "$DOCKER_STUB_LOG" "removed october-app:<none>"

echo "prune image tests passed"
