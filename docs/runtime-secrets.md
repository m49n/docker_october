# Runtime Secrets

`.env.example` is a list of variables the application needs. It is not a recommendation to commit or bake real secrets into Docker images.

## Simple VPS Mode

For one Debian/VPS server with Docker Compose, a server-side `.env` file is acceptable:

```bash
cp .env.example .env
nano .env
chmod 600 .env
```

Compose reads it through:

```yaml
env_file:
  - .env
```

This is simple, but the server filesystem now contains secrets. Keep access limited, avoid copying `.env` into backups without encryption and never commit it.

## Orchestrator Mode

For Kubernetes, BeCloud-like platforms, Docker Swarm or hosted container platforms, use the platform's runtime configuration mechanism:

- Secrets for passwords, tokens, API keys and private credentials
- ConfigMaps or plain environment variables for non-secret settings
- External secret managers such as Vault, Doppler, Infisical, 1Password or a cloud secret manager when central rotation and audit are required

The container should receive variables such as:

```text
APP_KEY
DB_PASSWORD
REDIS_PASSWORD
MAIL_PASSWORD
KAFKA_SASL_PASSWORD
```

at runtime. They should not be copied into the image and should not exist in git.

## Build Secrets Are Separate

OctoberCMS Composer credentials are build-time secrets, not runtime app settings.

Use BuildKit secrets for Composer:

```bash
docker build --secret id=composer_auth,src=auth.json --target app -t october-app:test .
```

or in CI:

```bash
docker build --secret id=composer_auth,env=COMPOSER_AUTH --target app -t october-app:$IMAGE_TAG .
```

Do not pass Composer credentials through Dockerfile `ARG` or `ENV`.
