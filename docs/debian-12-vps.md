# Debian 12 VPS Deployment

This guide describes a simple single-server production deployment for a Debian 12 VPS with 2 CPU, 4 GB RAM and 100 GB SSD.

For higher availability or multi-server deployments, build images in CI/CD, push them to a registry, use external PostgreSQL/Redis and store media in S3 or MinIO.

Prerequisite: the OctoberCMS project already exists in git and already contains this Docker kit in the project root. The server should not install OctoberCMS manually; it should build or pull Docker images from the project repository.

## 1. DNS

Create DNS records at your domain provider:

```text
A     example.com      <server-ip>
A     www.example.com  <server-ip>
```

Wait until DNS resolves:

```bash
dig +short example.com
dig +short www.example.com
```

## 2. Server Basics

Connect to the server:

```bash
ssh root@<server-ip>
```

Update packages:

```bash
apt update
apt upgrade -y
apt install -y ca-certificates curl dnsutils git gnupg ufw
```

Create a deploy user:

```bash
adduser deploy
usermod -aG sudo deploy
```

Allow SSH, HTTP and HTTPS:

```bash
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

Docker can publish container ports outside normal UFW expectations, so bind the app's internal nginx to `127.0.0.1:8080` and expose only Caddy on ports `80` and `443`.

## 3. Install Docker

Install Docker Engine and the Compose plugin from Docker's official Debian repository:

```bash
apt install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
docker run --rm hello-world
```

Allow the deploy user to run Docker:

```bash
usermod -aG docker deploy
```

Reconnect as `deploy` before running Docker commands:

```bash
exit
ssh deploy@<server-ip>
```

## 4. Install Caddy For HTTPS

Caddy terminates HTTPS and proxies traffic to the Docker nginx container on localhost.

Install Caddy:

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

Create `/etc/caddy/Caddyfile`:

```caddyfile
example.com, www.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

Reload Caddy:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Caddy will request and renew Let's Encrypt certificates automatically when DNS points to the server and ports `80` and `443` are open.

## 5. Prepare Project

Clone the OctoberCMS project repository:

```bash
sudo mkdir -p /opt/october
sudo chown deploy:deploy /opt/october
cd /opt/october
git clone git@github.com:owner/project.git app
cd app
```

The project repository should already contain this Docker kit in its root:

```text
Dockerfile
docker-compose.prod.yml
docker/
.env.example
auth.json.example
```

Create runtime env:

```bash
cp .env.example .env
nano .env
```

For bundled PostgreSQL on the same VPS, set:

```env
APP_ENV=production
APP_DEBUG=false
APP_URL=https://example.com
HTTP_PORT=127.0.0.1:8080

DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=october
DB_USERNAME=october
DB_PASSWORD=<strong-db-password>

POSTGRES_DB=october
POSTGRES_USER=october
POSTGRES_PASSWORD=<strong-db-password>

REDIS_HOST=redis
CACHE_STORE=redis
CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
LOG_CHANNEL=stderr

APP_IMAGE=october-app
NGINX_IMAGE=october-nginx
IMAGE_TAG=local
```

For external PostgreSQL, do not use `--profile local-db` and set `DB_HOST`, `DB_DATABASE`, `DB_USERNAME` and `DB_PASSWORD` to the external database values.

## 6. Composer Authentication

Create `auth.json` from the example:

```bash
cp auth.json.example auth.json
nano auth.json
```

Set October Gateway credentials:

```json
{
  "http-basic": {
    "gateway.octobercms.com": {
      "username": "account@example.com",
      "password": "october-license-key"
    }
  }
}
```

Never commit `auth.json`.

## 7. Build Images On The VPS

This is the simplest flow for one server:

```bash
export IMAGE_TAG=$(git rev-parse --short HEAD)

DOCKER_BUILDKIT=1 docker build \
  --secret id=composer_auth,src=auth.json \
  --target app \
  -t october-app:$IMAGE_TAG .

DOCKER_BUILDKIT=1 docker build \
  --target nginx \
  -t october-nginx:$IMAGE_TAG .
```

Update `.env` with the new tag:

```bash
sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=$IMAGE_TAG/" .env
```

## 8. Start Services

Start with bundled PostgreSQL:

```bash
docker compose -f docker-compose.prod.yml --profile local-db up -d
```

Start with external PostgreSQL:

```bash
docker compose -f docker-compose.prod.yml up -d
```

Check containers:

```bash
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs -f --tail=100 php-fpm
```

## 9. Run First Migrations

Run October migrations after containers start and PostgreSQL is reachable:

```bash
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan october:migrate --force
```

If the project has Laravel migrations:

```bash
docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan migrate --force
```

Run these commands as explicit deploy steps. Do not run migrations automatically from every web container.

Or use the deploy helper after images are built:

```bash
chmod +x scripts/deploy.sh
DEPLOY_PULL=0 USE_LOCAL_DB=1 ./scripts/deploy.sh
```

## 10. Open The Site

Check locally from the server:

```bash
curl -I http://127.0.0.1:8080
curl -I https://example.com
```

Then open:

```text
https://example.com
```

## 11. Updating The Project

For local build on the VPS:

```bash
cd /opt/october/app
git pull

export IMAGE_TAG=$(git rev-parse --short HEAD)

DOCKER_BUILDKIT=1 docker build \
  --secret id=composer_auth,src=auth.json \
  --target app \
  -t october-app:$IMAGE_TAG .

DOCKER_BUILDKIT=1 docker build \
  --target nginx \
  -t october-nginx:$IMAGE_TAG .

sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=$IMAGE_TAG/" .env
DEPLOY_PULL=0 USE_LOCAL_DB=1 ./scripts/deploy.sh
```

Recommended production flow:

```text
git push
CI/CD builds app and nginx images
CI/CD pushes images to a registry
server pulls new images
server runs migrations
server restarts containers
```

With a registry, the VPS does not need `auth.json` or Composer credentials. It only needs permission to pull images.
