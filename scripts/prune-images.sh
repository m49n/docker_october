#!/usr/bin/env sh
set -eu

IMAGE_KEEP_COUNT="${IMAGE_KEEP_COUNT:-5}"
IMAGE_PRUNE_DRY_RUN="${IMAGE_PRUNE_DRY_RUN:-1}"
IMAGE_PRUNE_KEEP_TAGS="${IMAGE_PRUNE_KEEP_TAGS:-}"

get_env_value() {
    key="$1"
    if [ -f .env ]; then
        grep -E "^${key}=" .env | tail -n 1 | cut -d= -f2- || true
    fi
}

contains_word() {
    list="$1"
    value="$2"
    for item in $list; do
        if [ "$item" = "$value" ]; then
            return 0
        fi
    done
    return 1
}

current_tag="$(get_env_value IMAGE_TAG)"
app_image="$(get_env_value APP_IMAGE)"
nginx_image="$(get_env_value NGINX_IMAGE)"
app_image="${app_image:-october-app}"
nginx_image="${nginx_image:-october-nginx}"

extra_keep_tags="$(printf '%s' "$IMAGE_PRUNE_KEEP_TAGS" | tr ',' ' ')"

prune_image_repo() {
    image_repo="$1"
    kept_count=0

    docker image ls "$image_repo" --format '{{.Repository}}:{{.Tag}}' | while IFS= read -r ref; do
        [ -n "$ref" ] || continue

        tag="${ref##*:}"
        if [ "$tag" = "<none>" ]; then
            continue
        fi

        kept_count=$((kept_count + 1))

        if [ "$tag" = "$current_tag" ]; then
            echo "KEEP current $ref"
            continue
        fi

        if contains_word "$extra_keep_tags" "$tag"; then
            echo "KEEP configured $ref"
            continue
        fi

        if [ "$kept_count" -le "$IMAGE_KEEP_COUNT" ]; then
            echo "KEEP recent $ref"
            continue
        fi

        if [ "$IMAGE_PRUNE_DRY_RUN" = "1" ]; then
            echo "DRY RUN remove $ref"
        else
            docker image rm "$ref"
        fi
    done
}

echo "Pruning images for $app_image and $nginx_image"
echo "IMAGE_KEEP_COUNT=$IMAGE_KEEP_COUNT"
echo "IMAGE_PRUNE_DRY_RUN=$IMAGE_PRUNE_DRY_RUN"
echo "Current IMAGE_TAG=${current_tag:-<unset>}"

prune_image_repo "$app_image"
prune_image_repo "$nginx_image"
