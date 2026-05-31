# Backup And Restore

Production is not ready until restore has been tested.

This guide covers the bundled single-server Docker Compose setup:

- PostgreSQL service from `--profile local-db`
- `storage-app` Docker volume for local media/uploads

For multi-server production, prefer external PostgreSQL backups from the database provider and S3/MinIO lifecycle/versioning for media.

## What To Back Up

Back up these items:

- PostgreSQL database
- `storage-app` volume when media/uploads are stored locally
- `.env` or the equivalent secret store export
- deployment notes such as image tag and git commit

Do not rely on Redis as the source of truth. Redis is used for cache, sessions and queue state.

## Backup Directory

Create a host-side backup directory:

```bash
sudo mkdir -p /var/backups/october
sudo chown "$USER:$USER" /var/backups/october
chmod 700 /var/backups/october
```

Set common variables:

```bash
cd /opt/october/app
export BACKUP_DIR=/var/backups/october
export BACKUP_TAG=$(date -u +%Y%m%dT%H%M%SZ)
```

## Automated Backup

Use the helper script for the bundled single-server setup:

```bash
cd /opt/october/app
BACKUP_DIR=/var/backups/october USE_LOCAL_DB=1 ./scripts/backup.sh
```

The script creates:

- `postgres-<tag>.dump`
- `storage-app-<tag>.tar.gz`
- `metadata-<tag>.txt`

Secrets are not copied by default. To include `.env` and `auth.json` in the backup directory:

```bash
BACKUP_INCLUDE_SECRETS=1 BACKUP_DIR=/var/backups/october USE_LOCAL_DB=1 ./scripts/backup.sh
```

Store secret backups carefully: restrict permissions, encrypt them and move them off-server.

## Daily Backup Timer

Install a systemd timer on a single VPS:

```bash
cd /opt/october/app
BACKUP_DIR=/var/backups/october ./scripts/install-backup-timer.sh
```

Defaults:

- service: `october-backup.service`
- timer: `october-backup.timer`
- schedule: daily at `03:15` UTC with up to `15m` randomized delay
- retention: keep the newest `14` files for each backup type
- secrets: not included

Customize the schedule:

```bash
BACKUP_ON_CALENDAR='*-*-* 02:30:00' \
BACKUP_RANDOMIZED_DELAY_SEC=20m \
BACKUP_RETENTION_COUNT=21 \
./scripts/install-backup-timer.sh
```

Check the timer:

```bash
systemctl list-timers october-backup.timer
systemctl status october-backup.timer
journalctl -u october-backup.service -n 100 --no-pager
```

Run a manual timer job:

```bash
systemctl start october-backup.service
```

## PostgreSQL Backup

Create a compressed custom-format dump:

```bash
docker compose -f docker-compose.prod.yml --profile local-db exec -T postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-acl \
  > "$BACKUP_DIR/postgres-$BACKUP_TAG.dump"
```

Create a plain SQL dump when you need easy inspection:

```bash
docker compose -f docker-compose.prod.yml --profile local-db exec -T postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-acl \
  | gzip > "$BACKUP_DIR/postgres-$BACKUP_TAG.sql.gz"
```

Record metadata:

```bash
{
  echo "date_utc=$BACKUP_TAG"
  echo "git_commit=$(git rev-parse HEAD)"
  echo "image_tag=$(grep -E '^IMAGE_TAG=' .env | cut -d= -f2-)"
  docker compose -f docker-compose.prod.yml ps
} > "$BACKUP_DIR/metadata-$BACKUP_TAG.txt"
```

## Storage Volume Backup

Back up `storage-app`:

```bash
docker run --rm \
  -v october-production_storage-app:/data:ro \
  -v "$BACKUP_DIR:/backup" \
  alpine:3.20 \
  tar -czf "/backup/storage-app-$BACKUP_TAG.tar.gz" -C /data .
```

If the project uses S3 or MinIO for media, do not back up `storage-app` as the source of truth. Back up the bucket through the storage provider's tooling.

## Secret Backup

For simple VPS mode, copy `.env` into the backup directory with restricted permissions:

```bash
cp .env "$BACKUP_DIR/env-$BACKUP_TAG"
chmod 600 "$BACKUP_DIR/env-$BACKUP_TAG"
```

For Vault, Kubernetes, BeCloud-like platforms or Docker Swarm, export secrets using the platform's official backup process. Do not invent a second shadow secret store.

## Encrypt And Move Backups Off-Server

At minimum, move backups off the VPS:

```bash
rsync -av --progress "$BACKUP_DIR/" backup-user@backup-host:/srv/backups/october/
```

Prefer encryption before upload. Example with `age`:

```bash
tar -C "$BACKUP_DIR" -czf - \
  "postgres-$BACKUP_TAG.dump" \
  "storage-app-$BACKUP_TAG.tar.gz" \
  "metadata-$BACKUP_TAG.txt" \
  | age -r age1examplepublickey -o "$BACKUP_DIR/october-$BACKUP_TAG.tar.gz.age"
```

Use your organization's approved encryption and retention policy.

## Restore PostgreSQL

Stop app containers that may write to the database:

```bash
docker compose -f docker-compose.prod.yml stop nginx php-fpm queue scheduler
```

Drop and recreate the database:

```bash
docker compose -f docker-compose.prod.yml --profile local-db exec -T postgres \
  dropdb -U "$POSTGRES_USER" --if-exists "$POSTGRES_DB"

docker compose -f docker-compose.prod.yml --profile local-db exec -T postgres \
  createdb -U "$POSTGRES_USER" "$POSTGRES_DB"
```

Restore the custom-format dump:

```bash
cat "$BACKUP_DIR/postgres-20260530T120000Z.dump" \
  | docker compose -f docker-compose.prod.yml --profile local-db exec -T postgres \
      pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --no-acl
```

Start services:

```bash
docker compose -f docker-compose.prod.yml --profile local-db up -d
```

Run migrations only after confirming the restored project version expects them:

```bash
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan october:migrate --force
```

## Restore Storage Volume

Stop app containers:

```bash
docker compose -f docker-compose.prod.yml stop nginx php-fpm queue scheduler
```

Restore into `storage-app`:

```bash
docker run --rm \
  -v october-production_storage-app:/data \
  -v "$BACKUP_DIR:/backup:ro" \
  alpine:3.20 \
  sh -c 'rm -rf /data/* && tar -xzf /backup/storage-app-20260530T120000Z.tar.gz -C /data'
```

Fix ownership through the app image:

```bash
docker compose -f docker-compose.prod.yml run --rm php-fpm \
  sh -c 'chown -R www-data:www-data /var/www/html/storage/app'
```

Start services:

```bash
docker compose -f docker-compose.prod.yml --profile local-db up -d
```

## Restore Test Checklist

Run this on a staging server or disposable VPS before trusting backups:

1. Start empty PostgreSQL and Redis volumes.
2. Restore PostgreSQL dump.
3. Restore `storage-app`.
4. Start the app image for the metadata git commit/image tag.
5. Open the site and backend.
6. Check uploaded media.
7. Run:

```bash
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs --tail=100 php-fpm nginx queue scheduler
```

## Suggested Schedule

For a small production site:

- PostgreSQL: daily, keep 14 daily and 4 weekly copies
- `storage-app`: daily or after content-heavy changes
- `.env` or secret export: after every secret change
- restore test: monthly or before major releases

Adjust retention for client contracts, legal requirements and available storage.
