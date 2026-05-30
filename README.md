# OctoberCMS Production Docker Kit

Production Docker template for OctoberCMS v4 projects.

The repository contains infrastructure files only. Install OctoberCMS in your project first, then copy this kit into the project root.

## What It Provides

- `app` Docker target based on `php:8.4-fpm-bookworm`
- `nginx` Docker target based on `nginx:1.27-alpine`
- PHP-FPM, queue worker, scheduler and Redis services
- Optional PostgreSQL service for single-server or staging deployments
- Composer authentication through BuildKit secrets
- Production PHP, OPcache and Nginx configuration
- Nginx hardening for root-based OctoberCMS deployments without requiring `public/` mirror
- Healthchecks, Docker log rotation and a deploy helper script

## Documentation

- [Installing OctoberCMS With This Kit](docs/install-october.md)
- [Production Deployment](docs/production-deploy.md)
- [Runtime Secrets](docs/runtime-secrets.md)
- [CI/CD Notes](docs/ci-cd.md)
- [Debian 12 VPS Deployment](docs/debian-12-vps.md)

## Quick Start

Create or open an OctoberCMS v4 project:

```bash
composer create-project october/october my-site
cd my-site
php artisan october:install
php artisan october:migrate
```

Copy this kit into the project root:

```bash
git clone https://github.com/m49n/docker_october.git /tmp/docker_october
rsync -av --exclude=".git" /tmp/docker_october/ ./
```

Create runtime environment:

```bash
cp .env.example .env
php artisan key:generate
```

Create local Composer auth file from the example:

```bash
cp auth.json.example auth.json
```

Edit `auth.json` and set the OctoberCMS account email and license key. Never commit the real `auth.json`.

Build images:

```bash
DOCKER_BUILDKIT=1 docker build \
  --secret id=composer_auth,src=auth.json \
  --target app \
  -t october-app:test .

DOCKER_BUILDKIT=1 docker build \
  --target nginx \
  -t october-nginx:test .
```

Run production compose with locally built images:

```bash
APP_IMAGE=october-app NGINX_IMAGE=october-nginx IMAGE_TAG=test \
docker compose -f docker-compose.prod.yml up -d
```

Run migrations as an explicit deploy step:

```bash
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan october:migrate --force
```

Or run the deploy helper after images are built:

```bash
DEPLOY_PULL=0 USE_LOCAL_DB=1 ./scripts/deploy.sh
```

## CI/CD Build

Use a CI secret named `COMPOSER_AUTH` containing the JSON from `auth.json.example`.

```bash
docker build \
  --secret id=composer_auth,env=COMPOSER_AUTH \
  --target app \
  -t registry.example.com/project/october-app:$IMAGE_TAG .

docker build \
  --target nginx \
  -t registry.example.com/project/october-nginx:$IMAGE_TAG .

docker push registry.example.com/project/october-app:$IMAGE_TAG
docker push registry.example.com/project/october-nginx:$IMAGE_TAG
```

Deploy:

```bash
export IMAGE_TAG=2026-05-22-001
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan october:migrate --force
```

## Services

- `nginx`: public HTTP entrypoint
- `php-fpm`: web PHP runtime
- `queue`: scalable queue worker
- `scheduler`: single scheduler container, do not scale this service
- `redis`: cache, sessions and queues
- `postgres`: optional profile, enable with `--profile local-db`

Run with optional PostgreSQL:

```bash
docker compose -f docker-compose.prod.yml --profile local-db up -d
```

With this profile enabled, PostgreSQL runs as a separate container in the same Docker network. All scaled app containers connect to the same database service by using the service name as the host:

```env
DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=october
DB_USERNAME=october
DB_PASSWORD=change-me
```

This works for `php-fpm`, `queue` and `scheduler`, including when `php-fpm` or `queue` are scaled:

```bash
docker compose -f docker-compose.prod.yml --profile local-db up -d --scale php-fpm=3 --scale queue=3
```

Use the bundled `postgres` service for a single-server deployment, staging or demos. For multi-server production, use an external PostgreSQL server or managed database and set `DB_HOST` to that external host instead.

The shared `storage-app` volume is mounted into `php-fpm`, `queue`, `scheduler` and read-only into `nginx`. This lets nginx serve local public media paths such as `/storage/app/media` on a single server. For multi-host production, use S3 or MinIO instead of local storage.

## Deploy Helper

The repository includes `scripts/deploy.sh` for single-host Docker Compose deployments:

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

Useful options:

```bash
DEPLOY_PULL=0 ./scripts/deploy.sh          # use locally built images
USE_LOCAL_DB=1 ./scripts/deploy.sh         # include the bundled postgres profile
RUN_LARAVEL_MIGRATIONS=1 ./scripts/deploy.sh
RUN_OPTIMIZE=1 ./scripts/deploy.sh
```

The script starts infrastructure services, runs `october:migrate --force`, optionally runs Laravel migrations and `artisan optimize`, signals queue and scheduler workers, then updates containers.

## Production Notes

- Do not commit `.env` or `auth.json`.
- Treat `.env.example` as the runtime configuration contract, not as a requirement to store production secrets in a file.
- For a simple single-server VPS, a server-side `.env` file is acceptable when permissions are restricted with `chmod 600 .env`.
- For orchestrators such as Kubernetes, BeCloud-like platforms or Docker Swarm, store runtime values in platform Secrets/ConfigMaps or Vault and inject them into containers at runtime.
- Do not run `composer install` when a container starts.
- Do not store `vendor` in a Docker volume.
- Do not run scheduler in every web container.
- Do not run migrations automatically in every container.
- Use Redis for cache, sessions and queue in multi-container deployments.
- Use S3 or MinIO for media when running more than one host. A named Docker volume is acceptable only for a single-server deployment.
- Default PHP limits are conservative: `memory_limit=128M`, `upload_max_filesize=32M`, `post_max_size=40M`. Raise them per project when imports, media handling or heavy backend operations need more headroom.
- Nginx keeps `root /var/www/html` for compatibility, but denies root-sensitive files and internal October/Laravel directories. For stricter deployments, migrate projects to October's `public/` mirror model separately.

## Verification

After copying the kit into a real OctoberCMS project:

```bash
docker run --rm october-app:test php -m
docker run --rm october-app:test composer dump-autoload --no-dev --optimize
docker run --rm --env-file .env october-app:test php artisan list
docker run --rm october-nginx:test nginx -t
```

The PHP extension list should include `pdo_pgsql`, `pgsql`, `redis`, `rdkafka`, `opcache`, `intl`, `zip`, `gd`, `bcmath`, `soap`, `curl`, `mbstring` and `SimpleXML`.
