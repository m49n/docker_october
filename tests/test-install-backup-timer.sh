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
systemd_dir="$tmp_dir/systemd"
backup_dir="$tmp_dir/backups"
bin_dir="$tmp_dir/bin"
mkdir -p "$workspace/scripts" "$systemd_dir" "$bin_dir"

cp "$repo_root/scripts/install-backup-timer.sh" "$workspace/scripts/install-backup-timer.sh"
touch "$workspace/scripts/backup.sh"
chmod +x "$workspace/scripts/install-backup-timer.sh" "$workspace/scripts/backup.sh"

cat > "$bin_dir/systemctl" <<'SH'
#!/usr/bin/env sh
set -eu
printf '%s\n' "systemctl $*" >> "$SYSTEMCTL_STUB_LOG"
SH
chmod +x "$bin_dir/systemctl"

cat > "$bin_dir/sudo" <<'SH'
#!/usr/bin/env sh
set -eu
printf '%s\n' "sudo $*" >> "$SUDO_STUB_LOG"
exec "$@"
SH
chmod +x "$bin_dir/sudo"

export PATH="$bin_dir:$PATH"
export SYSTEMCTL_STUB_LOG="$tmp_dir/systemctl.log"
export SYSTEMD_DIR="$systemd_dir"
export BACKUP_PROJECT_DIR="$workspace"
export BACKUP_DIR="$backup_dir"
export BACKUP_USER="codex"
export BACKUP_GROUP="codex"
export BACKUP_ON_CALENDAR="*-*-* 02:30:00"
export BACKUP_RANDOMIZED_DELAY_SEC="20m"
export BACKUP_RETENTION_COUNT="21"
export BACKUP_UNIT_NAME="october-test-backup"

cd "$workspace"
./scripts/install-backup-timer.sh >/tmp/install-backup-timer.out

service_file="$systemd_dir/october-test-backup.service"
timer_file="$systemd_dir/october-test-backup.timer"

test -f "$service_file" || fail "service file was not created"
test -f "$timer_file" || fail "timer file was not created"
test -d "$backup_dir" || fail "backup dir was not created"

assert_contains "$service_file" "User=codex"
assert_contains "$service_file" "Group=codex"
assert_contains "$service_file" "WorkingDirectory=$workspace"
assert_contains "$service_file" "Environment=BACKUP_DIR=$backup_dir"
assert_contains "$service_file" "Environment=USE_LOCAL_DB=1"
assert_contains "$service_file" "Environment=BACKUP_INCLUDE_SECRETS=0"
assert_contains "$service_file" "Environment=BACKUP_RETENTION_COUNT=21"
assert_contains "$service_file" "ExecStart=$workspace/scripts/backup.sh"
assert_contains "$timer_file" "OnCalendar=*-*-* 02:30:00"
assert_contains "$timer_file" "RandomizedDelaySec=20m"
assert_contains "$timer_file" "Persistent=true"
assert_contains "$timer_file" "Unit=october-test-backup.service"
assert_contains "$SYSTEMCTL_STUB_LOG" "systemctl daemon-reload"
assert_contains "$SYSTEMCTL_STUB_LOG" "systemctl enable --now october-test-backup.timer"
assert_contains /tmp/install-backup-timer.out "Installed october-test-backup.timer"

sudo_systemd_dir="$tmp_dir/sudo-systemd"
sudo_backup_dir="$tmp_dir/sudo-backups"
mkdir -p "$sudo_systemd_dir"
: > "$SYSTEMCTL_STUB_LOG"
export SUDO_STUB_LOG="$tmp_dir/sudo.log"
export SYSTEMD_DIR="$sudo_systemd_dir"
export BACKUP_DIR="$sudo_backup_dir"
export BACKUP_UNIT_NAME="october-sudo-backup"
export SYSTEMCTL_USE_SUDO="1"

./scripts/install-backup-timer.sh >/tmp/install-backup-timer-sudo.out

assert_contains "$SUDO_STUB_LOG" "sudo systemctl daemon-reload"
assert_contains "$SUDO_STUB_LOG" "sudo systemctl enable --now october-sudo-backup.timer"
assert_contains "$SYSTEMCTL_STUB_LOG" "systemctl daemon-reload"
assert_contains "$SYSTEMCTL_STUB_LOG" "systemctl enable --now october-sudo-backup.timer"
assert_contains /tmp/install-backup-timer-sudo.out "Installed october-sudo-backup.timer"

echo "install backup timer tests passed"
