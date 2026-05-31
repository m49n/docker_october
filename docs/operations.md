# Operations

Common commands for a single-server Docker Compose production deployment.

Run commands from the project root:

```bash
cd /opt/october/app
```

## Status

```bash
git status --short --branch
git rev-parse --short HEAD
grep '^IMAGE_TAG=' .env
docker compose -f docker-compose.prod.yml ps
```

## Health

```bash
curl -fsS -o /dev/null -w 'site_http=%{http_code}\n' http://127.0.0.1:8080/
curl -fsS -o /dev/null -w 'health_http=%{http_code}\n' http://127.0.0.1:8080/nginx-health
```

Expected:

```text
site_http=200
health_http=200
```

## Logs

```bash
docker compose -f docker-compose.prod.yml logs --tail=100 php-fpm nginx
docker compose -f docker-compose.prod.yml logs --tail=100 queue scheduler
docker compose -f docker-compose.prod.yml logs --tail=100 postgres redis
```

Follow logs:

```bash
docker compose -f docker-compose.prod.yml logs -f --tail=100 php-fpm nginx
```

## Artisan

Run an artisan command in a temporary app container:

```bash
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan list
```

Examples:

```bash
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan october:migrate --force
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan cache:clear
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan config:clear
```

## Queue And Scheduler

Restart queue workers gracefully:

```bash
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan queue:restart
docker compose -f docker-compose.prod.yml up -d queue
```

Interrupt scheduler after deploy/config changes:

```bash
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan schedule:interrupt
docker compose -f docker-compose.prod.yml up -d scheduler
```

Do not scale `scheduler`.

## Deploy

Manual deploy after images are built locally:

```bash
DEPLOY_PULL=0 USE_LOCAL_DB=1 ./scripts/deploy.sh
```

CI/CD normally runs this through `scripts/ci-deploy-over-ssh.sh`.

## Rollback

List available tags:

```bash
docker images october-app --format 'table {{.Repository}}\t{{.Tag}}\t{{.CreatedSince}}'
docker images october-nginx --format 'table {{.Repository}}\t{{.Tag}}\t{{.CreatedSince}}'
```

Rollback to a known-good tag:

```bash
USE_LOCAL_DB=1 ./scripts/rollback.sh <previous-image-tag>
```

Rollback does not revert database migrations or content.

## Backup

Create a backup:

```bash
BACKUP_DIR=/var/backups/october USE_LOCAL_DB=1 ./scripts/backup.sh
```

Include `.env` and `auth.json` only when the backup location is protected:

```bash
BACKUP_INCLUDE_SECRETS=1 BACKUP_DIR=/var/backups/october USE_LOCAL_DB=1 ./scripts/backup.sh
```

Move backups off-server and test restore regularly. See [Backup And Restore](backup-restore.md).

## Image Cleanup

Preview cleanup. This keeps the current `IMAGE_TAG` and the newest tags:

```bash
IMAGE_KEEP_COUNT=5 ./scripts/prune-images.sh
```

Apply cleanup:

```bash
IMAGE_KEEP_COUNT=5 IMAGE_PRUNE_DRY_RUN=0 ./scripts/prune-images.sh
```

Keep extra tags explicitly:

```bash
IMAGE_KEEP_COUNT=5 IMAGE_PRUNE_KEEP_TAGS="known-good-tag another-tag" ./scripts/prune-images.sh
```

The script only targets `APP_IMAGE` and `NGINX_IMAGE` from `.env`, defaulting to `october-app` and `october-nginx`.

## Disk Usage

```bash
df -h
docker system df
docker volume ls
```

Do not run broad destructive cleanup commands such as `docker system prune -a` on production unless you have checked which rollback images and volumes will be removed.

## Caddy

Domain setup is intentionally separate. When DNS is ready, configure Caddy to reverse proxy the domain to:

```text
127.0.0.1:8080
```

See the server's `/etc/caddy/Caddyfile`.
