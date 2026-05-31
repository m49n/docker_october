# Bitbucket Pipelines Deployment

This workflow deploys without a container registry:

```text
push to Bitbucket main
Bitbucket Pipeline starts
Pipeline connects to the server over SSH
Server runs git pull
Server builds app and nginx images locally
Server runs scripts/deploy.sh
Pipeline sends Telegram success or failure notification
```

This fits a single VPS deployment. For larger production setups, build images in CI, push to a registry, and let the server pull immutable images.

## Files

- `bitbucket-pipelines.yml`
- `scripts/ci-deploy-over-ssh.sh`
- `scripts/telegram-notify.sh`
- `scripts/deploy.sh`

## Required Repository Variables

Configure these in Bitbucket repository variables or deployment variables:

```text
DEPLOY_HOST=89.207.252.234
DEPLOY_USER=codex
DEPLOY_PATH=/opt/october/app
DEPLOY_BRANCH=main
DEPLOY_USE_LOCAL_DB=1
```

Optional:

```text
DEPLOY_PORT=22
DEPLOY_RUN_LARAVEL_MIGRATIONS=0
DEPLOY_RUN_OPTIMIZE=0
DEPLOY_COMPOSE_FILE=docker-compose.prod.yml
DEPLOY_BUILD_SECRET_FILE=auth.json
```

## SSH Access

Use one of these approaches.

### Bitbucket Pipelines SSH Key

In Bitbucket, create or use the repository Pipelines SSH key and add its public key to the server user's `~/.ssh/authorized_keys`.

The server user must be able to:

- `cd` into `DEPLOY_PATH`
- run `git pull`
- run Docker commands
- read `auth.json` if Composer authentication is required during build

### Private Key Variable

Alternatively, store a private key in a secured variable:

```text
DEPLOY_SSH_PRIVATE_KEY=<private key content>
```

Then add the matching public key to the server user's `~/.ssh/authorized_keys`.

## Known Hosts

Recommended: store the server host key in a secured variable:

```text
DEPLOY_KNOWN_HOSTS=<ssh-keyscan output>
```

Generate it locally:

```bash
ssh-keyscan -p 22 example.com
```

If `DEPLOY_KNOWN_HOSTS` is not set, the script uses:

```text
StrictHostKeyChecking=accept-new
```

## Telegram Notifications

Create a Telegram bot through BotFather and add it to the target chat.

Set secured variables:

```text
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
```

Optional for forum topics:

```text
TELEGRAM_THREAD_ID=
```

Messages are sent for:

- deploy start
- deploy success
- deploy failure

## Composer Authentication

When the server builds images locally, Composer authentication should exist on the server as `auth.json` in the project root.

`auth.json` is excluded from git and Docker image context. During build, `scripts/ci-deploy-over-ssh.sh` passes it as a BuildKit secret when the file exists:

```bash
docker build --secret id=composer_auth,src=auth.json --target app ...
```

If all Composer packages are public or already cached, the build may work without `auth.json`, but do not rely on cache for production.

## First Manual Test

Before enabling the pipeline, test the remote deploy command locally:

```bash
DEPLOY_HOST=89.207.252.234 \
DEPLOY_USER=codex \
DEPLOY_PATH=/opt/october/app \
DEPLOY_USE_LOCAL_DB=1 \
./scripts/ci-deploy-over-ssh.sh
```

Then push to `main` and check the Bitbucket pipeline log.
