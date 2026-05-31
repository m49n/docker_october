# Production Deployment

## Build

```bash
export IMAGE_TAG=2026-05-22-001

docker build \
  --secret id=composer_auth,env=COMPOSER_AUTH \
  --target app \
  -t registry.example.com/project/october-app:$IMAGE_TAG .

docker build \
  --target nginx \
  -t registry.example.com/project/october-nginx:$IMAGE_TAG .
```

## Push

```bash
docker push registry.example.com/project/october-app:$IMAGE_TAG
docker push registry.example.com/project/october-nginx:$IMAGE_TAG
```

## Runtime Env

`.env.example` is the contract for required runtime variables. Do not commit real values.

For a simple single-server VPS, create `.env` on the server from `.env.example`, restrict file permissions and fill the values:

```bash
cp .env.example .env
chmod 600 .env
```

For Kubernetes, BeCloud-like platforms, Docker Swarm or a Vault-based setup, do not rely on a project `.env` file. Store secrets in the platform secret manager or Vault and inject them into the app, queue and scheduler containers at runtime.

Required values:

- `APP_KEY`
- `APP_URL`
- `BACKEND_URI`
- `DB_HOST`
- `DB_DATABASE`
- `DB_USERNAME`
- `DB_PASSWORD`
- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` when using the bundled `postgres` profile
- `REDIS_HOST`
- `MAIL_*`
- `KAFKA_*`
- `HTTP_PORT`, for example `127.0.0.1:8080` when HTTPS is handled by a host reverse proxy
- `APP_IMAGE`
- `NGINX_IMAGE`
- `IMAGE_TAG`

## Deploy

Using the helper script:

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

For a local VPS build where images were built on the server and PostgreSQL is bundled:

```bash
DEPLOY_PULL=0 USE_LOCAL_DB=1 ./scripts/deploy.sh
```

For registry-based deployment with external PostgreSQL:

```bash
./scripts/deploy.sh
```

Useful flags:

```bash
DEPLOY_PULL=0                 # skip docker compose pull, use local images
USE_LOCAL_DB=1                # enable the bundled postgres compose profile
RUN_LARAVEL_MIGRATIONS=1      # also run php artisan migrate --force
RUN_OPTIMIZE=1                # also run php artisan optimize
```

Manual equivalent:

```bash
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan october:migrate --force
```

If the project also has Laravel migrations:

```bash
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan migrate --force
```

## Rollback

To switch back to a previously built app/nginx image tag:

```bash
USE_LOCAL_DB=1 ./scripts/rollback.sh <previous-image-tag>
```

The rollback helper updates `IMAGE_TAG`, recreates services and waits for `php-fpm` and `nginx`. It does not run migrations and does not revert database changes. See [Rollback](rollback.md).

## Scaling

Scale PHP-FPM and queue workers:

```bash
docker compose -f docker-compose.prod.yml up -d --scale php-fpm=2 --scale queue=3
```

Do not scale `scheduler`. It must run as a single container. For critical scheduled tasks, use `onOneServer()` and `withoutOverlapping()` with Redis-backed cache locks.

## Storage

For a single server, the `storage-app` named volume preserves `storage/app`.

For multi-host production, use S3 or MinIO for uploads and media. Do not rely on a local container filesystem for `storage/app/uploads` or `storage/app/media`.

The compose file mounts `storage-app` read-only into `nginx`, so local public media can be served directly by nginx on a single server.

Before going live, configure and test backups for PostgreSQL, `storage-app` and runtime secrets. See [Backup And Restore](backup-restore.md).

## Backup

Create an on-demand backup on the server:

```bash
BACKUP_DIR=/var/backups/october USE_LOCAL_DB=1 ./scripts/backup.sh
```

The helper writes PostgreSQL, `storage-app` and metadata backups. It does not copy `.env` or `auth.json` unless `BACKUP_INCLUDE_SECRETS=1` is set.

Install the daily systemd backup timer:

```bash
BACKUP_DIR=/var/backups/october ./scripts/install-backup-timer.sh
```

## Health And Logs

The compose file includes healthchecks for `nginx`, `php-fpm`, `redis` and bundled `postgres`.

Docker logs use the `local` logging driver with rotation:

```yaml
logging:
  driver: local
  options:
    max-size: "10m"
    max-file: "3"
```
