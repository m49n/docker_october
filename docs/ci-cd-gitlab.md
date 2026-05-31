# GitLab CI/CD Deployment

This workflow deploys without a container registry:

```text
push to GitLab default branch
GitLab CI starts
CI job connects to the server over SSH
Server runs git pull
Server builds app and nginx images locally
Server runs scripts/deploy.sh
CI job sends Telegram success or failure notification
```

This fits a single VPS deployment. For larger production setups, build images in CI, push to a registry, and let the server pull immutable images.

## Files

- `gitlab-ci.example.yml`
- `.gitlab-ci.yml` in projects that use GitLab
- `scripts/ci-deploy-over-ssh.sh`
- `scripts/telegram-notify.sh`
- `scripts/deploy.sh`

## Enable GitLab CI

Copy the example file to GitLab's active CI file:

```bash
cp gitlab-ci.example.yml .gitlab-ci.yml
git add .gitlab-ci.yml gitlab-ci.example.yml
git commit -m "Add GitLab production deploy pipeline"
git push
```

The example deploys only from the default branch:

```yaml
rules:
  - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
```

For production, keep the default branch protected and mark production variables as protected.

## Required CI/CD Variables

Configure these in GitLab:

```text
Project -> Settings -> CI/CD -> Variables
```

Required variables:

```text
DEPLOY_HOST=89.207.252.234
DEPLOY_USER=codex
DEPLOY_PATH=/opt/october/app
DEPLOY_BRANCH=main
DEPLOY_USE_LOCAL_DB=1
```

Optional variables:

```text
DEPLOY_PORT=22
DEPLOY_RUN_LARAVEL_MIGRATIONS=0
DEPLOY_RUN_OPTIMIZE=0
DEPLOY_COMPOSE_FILE=docker-compose.prod.yml
DEPLOY_BUILD_SECRET_FILE=auth.json
DEPLOY_STRICT_HOST_KEY_CHECKING=yes
```

For production variables:

- enable `Protect variable` when the deploy branch is protected
- set environment scope to `production` if the project uses environment-scoped variables
- do not print variable values in job logs

## SSH Access From GitLab To Server

Create a dedicated deploy key pair for GitLab CI:

```bash
ssh-keygen -t ed25519 -C "gitlab-ci-october-deploy" -f gitlab_ci_deploy -N ""
```

Add the public key to the server user:

```bash
mkdir -p /home/codex/.ssh
cat gitlab_ci_deploy.pub >> /home/codex/.ssh/authorized_keys
chmod 700 /home/codex/.ssh
chmod 600 /home/codex/.ssh/authorized_keys
chown -R codex:codex /home/codex/.ssh
```

Add the private key in GitLab:

```text
Project -> Settings -> CI/CD -> Variables
Key: SSH_PRIVATE_KEY
Type: File
Value: contents of gitlab_ci_deploy
```

The private key file must end with a newline. The deploy script automatically uses GitLab file variables named `SSH_PRIVATE_KEY`.

Alternative variable names are also supported:

```text
DEPLOY_SSH_PRIVATE_KEY_FILE=/path/to/private/key/file
DEPLOY_SSH_PRIVATE_KEY=<private key content>
```

## Known Hosts

Recommended: store the server host key as a GitLab file variable.

Generate it locally:

```bash
ssh-keyscan -p 22 89.207.252.234 > ssh_known_hosts
```

Add it in GitLab:

```text
Project -> Settings -> CI/CD -> Variables
Key: SSH_KNOWN_HOSTS
Type: File
Value: contents of ssh_known_hosts
```

The deploy script automatically uses GitLab file variables named `SSH_KNOWN_HOSTS`.

Alternative variable names are also supported:

```text
DEPLOY_KNOWN_HOSTS_FILE=/path/to/known_hosts/file
DEPLOY_KNOWN_HOSTS=<ssh-keyscan output>
```

If known hosts are configured, set:

```text
DEPLOY_STRICT_HOST_KEY_CHECKING=yes
```

If no known hosts variable is configured, the script defaults to:

```text
StrictHostKeyChecking=accept-new
```

## Server Access To GitLab Repository

The CI job connects to the server, then the server runs:

```bash
git pull --ff-only origin main
```

For private repositories, the server itself must have read access to GitLab.

Add the server user's public SSH key to GitLab as a project deploy key:

```text
Project -> Settings -> Repository -> Deploy keys
```

Then test from the server:

```bash
ssh codex@89.207.252.234 'cd /opt/october/app && git ls-remote origin main'
```

## Telegram Notifications

Create a Telegram bot through BotFather and add it to the target chat.

Set CI/CD variables:

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

If Telegram variables are not configured, deploy still works and notifications are skipped.

## Composer Authentication

When the server builds images locally, Composer authentication should exist on the server as `auth.json` in the project root:

```text
/opt/october/app/auth.json
```

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

Then push to the default branch and check:

```text
Project -> Build -> Pipelines
```

## Emergency Rollback

This pipeline deploys the latest default branch commit. For a fast rollback to an already built image, run the server-side rollback helper:

```bash
cd /opt/october/app
USE_LOCAL_DB=1 ./scripts/rollback.sh <previous-image-tag>
```

See [Rollback](rollback.md) for limits and verification steps.

## References

- GitLab CI/CD variables: https://docs.gitlab.com/ci/variables/
- GitLab SSH keys in CI jobs: https://docs.gitlab.com/ci/jobs/ssh_keys/
- GitLab job rules: https://docs.gitlab.com/ci/jobs/job_rules/
