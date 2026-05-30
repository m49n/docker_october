#!/usr/bin/env sh
set -eu

TEMPLATE_REPO="${TEMPLATE_REPO:-https://github.com/m49n/docker_october.git}"
TEMPLATE_REF="${TEMPLATE_REF:-main}"
ALLOW_DIRTY="${UPDATE_KIT_ALLOW_DIRTY:-0}"
INCLUDE_README="${UPDATE_KIT_INCLUDE_README:-0}"
OVERWRITE_ENV_EXAMPLE="${UPDATE_KIT_OVERWRITE_ENV_EXAMPLE:-0}"
OVERWRITE_GITIGNORE="${UPDATE_KIT_OVERWRITE_GITIGNORE:-0}"
PRUNE_DOCKER_DIR="${UPDATE_KIT_PRUNE_DOCKER:-0}"

if ! command -v git >/dev/null 2>&1; then
    echo "git is required" >&2
    exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Run this script from the root of the OctoberCMS project git repository." >&2
    exit 1
fi

if [ "$ALLOW_DIRTY" != "1" ]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Working tree has tracked changes. Commit/stash them first, or run with UPDATE_KIT_ALLOW_DIRTY=1." >&2
        exit 1
    fi
fi

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

echo "Fetching Docker kit from $TEMPLATE_REPO ($TEMPLATE_REF)"
if ! git clone --depth 1 --branch "$TEMPLATE_REF" "$TEMPLATE_REPO" "$tmp_dir" >/dev/null 2>&1; then
    rm -rf "$tmp_dir"
    tmp_dir="$(mktemp -d)"
    git clone "$TEMPLATE_REPO" "$tmp_dir" >/dev/null
    git -C "$tmp_dir" checkout "$TEMPLATE_REF" >/dev/null
fi

copy_file() {
    src="$1"
    dest="$2"
    if [ -f "$tmp_dir/$src" ]; then
        mkdir -p "$(dirname "$dest")"
        cp -a "$tmp_dir/$src" "$dest"
    fi
}

copy_dir_contents() {
    src="$1"
    dest="$2"
    if [ -d "$tmp_dir/$src" ]; then
        mkdir -p "$dest"
        cp -a "$tmp_dir/$src/." "$dest/"
    fi
}

copy_file Dockerfile Dockerfile
copy_file docker-compose.prod.yml docker-compose.prod.yml
copy_file .dockerignore .dockerignore
copy_file .gitattributes .gitattributes
copy_file auth.json.example auth.json.example

if [ "$OVERWRITE_ENV_EXAMPLE" = "1" ] || [ ! -f .env.example ]; then
    copy_file .env.example .env.example
else
    copy_file .env.example .env.example.docker-kit
    echo "Kept existing .env.example; refreshed template saved as .env.example.docker-kit"
fi

if [ "$OVERWRITE_GITIGNORE" = "1" ] || [ ! -f .gitignore ]; then
    copy_file .gitignore .gitignore
else
    copy_file .gitignore .gitignore.docker-kit
    echo "Kept existing .gitignore; refreshed template saved as .gitignore.docker-kit"
fi

if [ "$INCLUDE_README" = "1" ] || [ ! -f README.md ]; then
    copy_file README.md README.md
else
    copy_file README.md README.docker-kit.md
    echo "Kept existing README.md; refreshed template saved as README.docker-kit.md"
fi

if [ "$PRUNE_DOCKER_DIR" = "1" ]; then
    rm -rf docker
fi

copy_dir_contents docker docker
copy_dir_contents docs docs
copy_dir_contents scripts scripts

chmod +x scripts/deploy.sh scripts/update-kit.sh 2>/dev/null || true

echo
echo "Docker kit sync complete. Review changes before committing:"
echo "  git status --short"
echo "  git diff --stat"
echo "  git diff"
echo
git status --short
