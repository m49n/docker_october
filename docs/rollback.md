# Rollback

Rollback switches Docker Compose back to a previously built app/nginx image tag.

This is a fast application rollback. It does not roll back the database schema or content. If a release ran destructive migrations or changed data in an incompatible way, restore PostgreSQL from backup or ship a forward fix.

## When To Use

Use rollback when:

- a deploy completed but the new application image is broken
- the previous image is still present on the server
- the database is compatible with the previous code

Do not use app-only rollback as the only recovery path for database problems. See [Backup And Restore](backup-restore.md).

## Find Available Tags

On the server:

```bash
cd /opt/october/app
docker images october-app --format 'table {{.Repository}}\t{{.Tag}}\t{{.CreatedSince}}'
docker images october-nginx --format 'table {{.Repository}}\t{{.Tag}}\t{{.CreatedSince}}'
```

For this kit, tags are normally short git commits, for example:

```text
add172f
4eb1738
```

## Roll Back On A Single VPS

Use the previous known-good tag:

```bash
cd /opt/october/app
USE_LOCAL_DB=1 ./scripts/rollback.sh 4eb1738
```

The script:

1. checks that `october-app:<tag>` and `october-nginx:<tag>` exist locally
2. updates `IMAGE_TAG` in `.env`
3. runs `docker compose up -d --remove-orphans`
4. waits for `php-fpm` and `nginx`
5. prints `docker compose ps`

If the deployment uses registry images instead of server-built local images, allow Compose to pull:

```bash
DEPLOY_PULL=1 ./scripts/rollback.sh 2026-05-31-001
```

## Verify

After rollback:

```bash
grep '^IMAGE_TAG=' .env
docker compose -f docker-compose.prod.yml ps
curl -fsS -o /dev/null -w 'site_http=%{http_code}\n' http://127.0.0.1:8080/
curl -fsS -o /dev/null -w 'health_http=%{http_code}\n' http://127.0.0.1:8080/nginx-health
```

Expected:

```text
site_http=200
health_http=200
```

## Roll Forward Again

Roll forward by switching back to the newer tag:

```bash
USE_LOCAL_DB=1 ./scripts/rollback.sh add172f
```

## CI/CD Notes

The Bitbucket and GitLab deploy jobs build and deploy the latest branch commit. For emergency rollback, run `scripts/rollback.sh` directly on the server. A later revert commit is still useful for source control, but it creates a new image and is not as fast as switching to an existing known-good tag.

## Limits

- Rollback requires the target app and nginx images to exist locally unless `DEPLOY_PULL=1`.
- Rollback does not run `october:migrate`.
- Rollback does not revert database migrations.
- Rollback does not restore `storage-app`.
- If a bad release changed data, use tested backups.
