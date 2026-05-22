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

Create `.env` on the server from `.env.example` and fill:

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

```bash
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan october:migrate --force
```

If the project also has Laravel migrations:

```bash
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan migrate --force
```

## Scaling

Scale PHP-FPM and queue workers:

```bash
docker compose -f docker-compose.prod.yml up -d --scale php-fpm=2 --scale queue=3
```

Do not scale `scheduler`. It must run as a single container. For critical scheduled tasks, use `onOneServer()` and `withoutOverlapping()` with Redis-backed cache locks.

## Storage

For a single server, the `storage-app` named volume preserves `storage/app`.

For multi-host production, use S3 or MinIO for uploads and media. Do not rely on a local container filesystem for `storage/app/uploads` or `storage/app/media`.
