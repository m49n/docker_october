# Installing OctoberCMS With This Kit

This kit is designed to be copied into an OctoberCMS v4 project root. It is not a complete OctoberCMS application by itself.

## New Project

Create OctoberCMS first:

```bash
composer create-project october/october my-site
cd my-site
php artisan october:install
php artisan october:migrate
```

Then copy the Docker kit:

```bash
git clone https://github.com/m49n/docker_october.git /tmp/docker_october
rsync -av --exclude=".git" /tmp/docker_october/ ./
```

If you are on Windows PowerShell:

```powershell
git clone https://github.com/m49n/docker_october.git "$env:TEMP\docker_october"
Copy-Item "$env:TEMP\docker_october\*" . -Recurse -Force
Copy-Item "$env:TEMP\docker_october\.dockerignore" . -Force
Copy-Item "$env:TEMP\docker_october\.env.example" . -Force
Copy-Item "$env:TEMP\docker_october\.gitignore" . -Force
```

## Composer Authentication

OctoberCMS uses Composer to install protected packages from the October Gateway. Keep authentication outside git.

Local file option:

```bash
cp auth.json.example auth.json
```

Edit `auth.json`:

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

CI secret option:

```bash
export COMPOSER_AUTH='{"http-basic":{"gateway.octobercms.com":{"username":"account@example.com","password":"october-license-key"}}}'
```

Build with file secret:

```bash
DOCKER_BUILDKIT=1 docker build --secret id=composer_auth,src=auth.json --target app -t october-app:test .
```

Build with env secret:

```bash
DOCKER_BUILDKIT=1 docker build --secret id=composer_auth,env=COMPOSER_AUTH --target app -t october-app:test .
```

Do not pass the October license with `ARG` or regular `ENV` in the Dockerfile. BuildKit secrets are mounted only for the Composer install step and are removed before the final image layer is created.

OctoberCMS also supports recreating Composer authentication with:

```bash
php artisan project:set <license-key>
```

For Docker image builds, prefer BuildKit secrets because Composer needs authentication during the `composer install` layer.
