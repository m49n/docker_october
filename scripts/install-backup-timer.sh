#!/usr/bin/env sh
set -eu

SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"
SYSTEMCTL_USE_SUDO="${SYSTEMCTL_USE_SUDO:-auto}"
BACKUP_PROJECT_DIR="${BACKUP_PROJECT_DIR:-$(pwd -P)}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/october}"
BACKUP_USER="${BACKUP_USER:-$(id -un)}"
BACKUP_GROUP="${BACKUP_GROUP:-$(id -gn)}"
BACKUP_UNIT_NAME="${BACKUP_UNIT_NAME:-october-backup}"
BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-*-*-* 03:15:00}"
BACKUP_RANDOMIZED_DELAY_SEC="${BACKUP_RANDOMIZED_DELAY_SEC:-15m}"
BACKUP_USE_LOCAL_DB="${BACKUP_USE_LOCAL_DB:-1}"
BACKUP_INCLUDE_SECRETS="${BACKUP_INCLUDE_SECRETS:-0}"
BACKUP_RETENTION_COUNT="${BACKUP_RETENTION_COUNT:-14}"
BACKUP_ENABLE_TIMER="${BACKUP_ENABLE_TIMER:-1}"

error() {
    echo "ERROR: $*" >&2
    exit 1
}

need_sudo() {
    path="$1"
    if [ "$(id -u)" = "0" ]; then
        return 1
    fi
    [ ! -w "$path" ]
}

run_privileged() {
    if [ "$(id -u)" = "0" ]; then
        "$@"
    else
        sudo "$@"
    fi
}

systemctl_needs_sudo() {
    if [ "$(id -u)" = "0" ]; then
        return 1
    fi

    case "$SYSTEMCTL_USE_SUDO" in
        1|true|yes)
            return 0
            ;;
        0|false|no)
            return 1
            ;;
        auto)
            [ "$SYSTEMCTL_BIN" = "systemctl" ] || return 1
            [ "$SYSTEMD_DIR" = "/etc/systemd/system" ] || return 1
            command -v sudo >/dev/null 2>&1 || return 1
            return 0
            ;;
        *)
            error "SYSTEMCTL_USE_SUDO must be auto, 1, or 0"
            ;;
    esac
}

run_systemctl() {
    if systemctl_needs_sudo; then
        sudo "$SYSTEMCTL_BIN" "$@"
    else
        "$SYSTEMCTL_BIN" "$@"
    fi
}

install_file() {
    src="$1"
    dest="$2"
    mode="$3"
    parent="$(dirname "$dest")"

    if need_sudo "$parent"; then
        run_privileged install -m "$mode" "$src" "$dest"
    else
        install -m "$mode" "$src" "$dest"
    fi
}

make_backup_dir() {
    if [ -d "$BACKUP_DIR" ] && [ -w "$BACKUP_DIR" ]; then
        chmod 700 "$BACKUP_DIR"
        return
    fi

    parent="$(dirname "$BACKUP_DIR")"
    if need_sudo "$parent"; then
        run_privileged mkdir -p "$BACKUP_DIR"
        run_privileged chown "$BACKUP_USER:$BACKUP_GROUP" "$BACKUP_DIR"
        run_privileged chmod 700 "$BACKUP_DIR"
    else
        mkdir -p "$BACKUP_DIR"
        chown "$BACKUP_USER:$BACKUP_GROUP" "$BACKUP_DIR" 2>/dev/null || true
        chmod 700 "$BACKUP_DIR"
    fi
}

case "$BACKUP_UNIT_NAME" in
    *[!A-Za-z0-9_.@-]*|"")
        error "BACKUP_UNIT_NAME contains unsupported characters"
        ;;
esac

if [ ! -f "$BACKUP_PROJECT_DIR/scripts/backup.sh" ]; then
    error "$BACKUP_PROJECT_DIR/scripts/backup.sh was not found"
fi

mkdir -p "$SYSTEMD_DIR" 2>/dev/null || true
make_backup_dir

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

service_file="$tmp_dir/$BACKUP_UNIT_NAME.service"
timer_file="$tmp_dir/$BACKUP_UNIT_NAME.timer"

cat > "$service_file" <<EOF
[Unit]
Description=October CMS production backup
Wants=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
User=$BACKUP_USER
Group=$BACKUP_GROUP
WorkingDirectory=$BACKUP_PROJECT_DIR
Environment=BACKUP_DIR=$BACKUP_DIR
Environment=USE_LOCAL_DB=$BACKUP_USE_LOCAL_DB
Environment=BACKUP_INCLUDE_SECRETS=$BACKUP_INCLUDE_SECRETS
Environment=BACKUP_RETENTION_COUNT=$BACKUP_RETENTION_COUNT
ExecStart=$BACKUP_PROJECT_DIR/scripts/backup.sh
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

cat > "$timer_file" <<EOF
[Unit]
Description=Run October CMS production backup

[Timer]
OnCalendar=$BACKUP_ON_CALENDAR
RandomizedDelaySec=$BACKUP_RANDOMIZED_DELAY_SEC
Persistent=true
Unit=$BACKUP_UNIT_NAME.service

[Install]
WantedBy=timers.target
EOF

install_file "$service_file" "$SYSTEMD_DIR/$BACKUP_UNIT_NAME.service" 0644
install_file "$timer_file" "$SYSTEMD_DIR/$BACKUP_UNIT_NAME.timer" 0644

run_systemctl daemon-reload

if [ "$BACKUP_ENABLE_TIMER" = "1" ]; then
    run_systemctl enable --now "$BACKUP_UNIT_NAME.timer"
else
    run_systemctl enable "$BACKUP_UNIT_NAME.timer"
fi

echo "Installed $BACKUP_UNIT_NAME.service"
echo "Installed $BACKUP_UNIT_NAME.timer"
echo "Backup directory: $BACKUP_DIR"
echo "Schedule: $BACKUP_ON_CALENDAR"
