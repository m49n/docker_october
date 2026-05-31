#!/usr/bin/env sh
set -eu

message="${1:-}"

if [ -z "$message" ]; then
    echo "Usage: $0 'message'" >&2
    exit 2
fi

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    echo "Telegram variables are not set; skipping notification." >&2
    exit 0
fi

api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

if [ -n "${TELEGRAM_THREAD_ID:-}" ]; then
    curl -fsS -X POST "$api_url" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "message_thread_id=${TELEGRAM_THREAD_ID}" \
        --data-urlencode "text=${message}" >/dev/null
else
    curl -fsS -X POST "$api_url" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" >/dev/null
fi
