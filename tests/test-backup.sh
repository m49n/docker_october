#!/usr/bin/env sh
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file_contains() {
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
backup_dir="$tmp_dir/backups"
mkdir -p "$workspace/scripts" "$bin_dir" "$backup_dir"

cp "$repo_root/scripts/backup.sh" "$workspace/scripts/backup.sh"
chmod +x "$workspace/scripts/backup.sh"

cat > "$workspace/.env" <<'ENV'
POSTGRES_DB=october_db
POSTGRES_USER=october_user
APP_IMAGE=october-app
NGINX_IMAGE=october-nginx
IMAGE_TAG=testtag
ENV

cat > "$workspace/auth.json" <<'JSON'
{"http-basic":{"gateway.octobercms.com":{"username":"user@example.com","password":"secret"}}}
JSON

touch "$workspace/docker-compose.prod.yml"

cat > "$bin_dir/git" <<'SH'
#!/usr/bin/env sh
set -eu
if [ "$1" = "rev-parse" ]; then
    printf 'abc123def456\n'
    exit 0
fi
exit 0
SH
chmod +x "$bin_dir/git"

cat > "$bin_dir/docker" <<'SH'
#!/usr/bin/env sh
set -eu
printf '%s\n' "docker $*" >> "$DOCKER_STUB_LOG"

for arg in "$@"; do
    if [ "$arg" = "pg_dump" ]; then
        printf 'PGDUMP'
        exit 0
    fi
done

if [ "$1" = "compose" ] && [ "$4" = "ps" ]; then
    printf 'compose ps ok\n'
    exit 0
fi

if [ "$1" = "compose" ] && [ "$5" = "ps" ]; then
    printf 'compose ps ok\n'
    exit 0
fi

if [ "$1" = "run" ]; then
    printf 'STORAGE' > "$BACKUP_DIR/storage-app-$BACKUP_TAG.tar.gz"
    exit 0
fi

if [ "$1" = "compose" ]; then
    printf 'PGDUMP'
    exit 0
fi

exit 0
SH
chmod +x "$bin_dir/docker"

export DOCKER_STUB_LOG="$tmp_dir/docker.log"
export BACKUP_DIR="$backup_dir"
export BACKUP_TAG="fixedtag"
export BACKUP_INCLUDE_SECRETS=1
export BACKUP_RETENTION_COUNT=1
export PATH="$bin_dir:$PATH"

printf 'OLD' > "$backup_dir/postgres-old.dump"
printf 'OLD' > "$backup_dir/storage-app-old.tar.gz"
printf 'OLD' > "$backup_dir/metadata-old.txt"
printf 'OLD' > "$backup_dir/env-old"
printf 'OLD' > "$backup_dir/auth-old.json"

cd "$workspace"
./scripts/backup.sh >/tmp/backup.out

test -s "$backup_dir/postgres-fixedtag.dump" || fail "postgres dump was not created"
test -s "$backup_dir/storage-app-fixedtag.tar.gz" || fail "storage archive was not created"
test -s "$backup_dir/metadata-fixedtag.txt" || fail "metadata was not created"
test -s "$backup_dir/env-fixedtag" || fail "env backup was not created"
test -s "$backup_dir/auth-fixedtag.json" || fail "auth backup was not created"
test ! -e "$backup_dir/postgres-old.dump" || fail "old postgres backup was not pruned"
test ! -e "$backup_dir/storage-app-old.tar.gz" || fail "old storage backup was not pruned"
test ! -e "$backup_dir/metadata-old.txt" || fail "old metadata backup was not pruned"
test ! -e "$backup_dir/env-old" || fail "old env backup was not pruned"
test ! -e "$backup_dir/auth-old.json" || fail "old auth backup was not pruned"

assert_file_contains "$backup_dir/postgres-fixedtag.dump" "PGDUMP"
assert_file_contains "$backup_dir/metadata-fixedtag.txt" "git_commit=abc123def456"
assert_file_contains "$backup_dir/metadata-fixedtag.txt" "image_tag=testtag"
assert_file_contains "$DOCKER_STUB_LOG" "docker compose -f docker-compose.prod.yml --profile local-db exec -T postgres pg_dump -U october_user -d october_db --format=custom --no-owner --no-acl"
assert_file_contains "$DOCKER_STUB_LOG" "docker run --rm -v october-production_storage-app:/data:ro -v $backup_dir:/backup alpine:3.20"
assert_file_contains "$DOCKER_STUB_LOG" "chown"
assert_file_contains /tmp/backup.out "Backup complete: fixedtag"

no_secrets_backup_dir="$tmp_dir/no-secrets-backups"
mkdir -p "$no_secrets_backup_dir"
export BACKUP_DIR="$no_secrets_backup_dir"
export BACKUP_TAG="nosecretstag"
export BACKUP_INCLUDE_SECRETS=0
export BACKUP_RETENTION_COUNT=1

printf 'OLD' > "$no_secrets_backup_dir/postgres-old.dump"
printf 'OLD' > "$no_secrets_backup_dir/storage-app-old.tar.gz"
printf 'OLD' > "$no_secrets_backup_dir/metadata-old.txt"

./scripts/backup.sh >/tmp/backup-no-secrets.out

test -s "$no_secrets_backup_dir/postgres-nosecretstag.dump" || fail "postgres dump without secrets was not created"
test -s "$no_secrets_backup_dir/storage-app-nosecretstag.tar.gz" || fail "storage archive without secrets was not created"
test -s "$no_secrets_backup_dir/metadata-nosecretstag.txt" || fail "metadata without secrets was not created"
test ! -e "$no_secrets_backup_dir/postgres-old.dump" || fail "old postgres backup without secrets was not pruned"
test ! -e "$no_secrets_backup_dir/storage-app-old.tar.gz" || fail "old storage backup without secrets was not pruned"
test ! -e "$no_secrets_backup_dir/metadata-old.txt" || fail "old metadata backup without secrets was not pruned"
assert_file_contains /tmp/backup-no-secrets.out "Backup complete: nosecretstag"

echo "backup tests passed"
