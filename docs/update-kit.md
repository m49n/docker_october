# Updating The Docker Kit In A Project

Use this workflow when `m49n/docker_october` receives global improvements and you need to bring them into an existing OctoberCMS project.

Do not edit production containers by hand. Update the project repository, commit the changes, build new images and deploy.

## Recommended Flow

From the OctoberCMS project root:

```bash
git status --short
./scripts/update-kit.sh
git diff --stat
git diff
git add Dockerfile docker-compose.prod.yml bitbucket-pipelines.yml gitlab-ci.example.yml .dockerignore .gitattributes auth.json.example docker docs scripts
git commit -m "Update production Docker kit"
git push
```

Then deploy normally:

```bash
export IMAGE_TAG=$(git rev-parse --short HEAD)

DOCKER_BUILDKIT=1 docker build --target app -t october-app:$IMAGE_TAG .
DOCKER_BUILDKIT=1 docker build --target nginx -t october-nginx:$IMAGE_TAG .

sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=$IMAGE_TAG/" .env
DEPLOY_PULL=0 USE_LOCAL_DB=1 ./scripts/deploy.sh
```

## What The Script Updates

The default sync updates:

- `Dockerfile`
- `docker-compose.prod.yml`
- `.dockerignore`
- `.gitattributes`
- `auth.json.example`
- `bitbucket-pipelines.yml` if it does not already exist
- `gitlab-ci.example.yml`
- `docker/`
- `docs/`
- `scripts/`

The script does not touch real secrets:

- `.env`
- `auth.json`
- `vendor/`
- `storage/`

## Files Kept Safe By Default

Projects often customize these files, so the script does not overwrite them by default:

- `.env.example`
- `.gitignore`
- `README.md`
- `bitbucket-pipelines.yml`

Instead, refreshed template versions are written to:

```text
.env.example.docker-kit
.gitignore.docker-kit
README.docker-kit.md
bitbucket-pipelines.docker-kit.yml
```

Review and merge them manually when needed.

## Useful Options

Overwrite `.env.example`:

```bash
UPDATE_KIT_OVERWRITE_ENV_EXAMPLE=1 ./scripts/update-kit.sh
```

Overwrite `.gitignore`:

```bash
UPDATE_KIT_OVERWRITE_GITIGNORE=1 ./scripts/update-kit.sh
```

Overwrite `README.md`:

```bash
UPDATE_KIT_INCLUDE_README=1 ./scripts/update-kit.sh
```

Overwrite `bitbucket-pipelines.yml`:

```bash
UPDATE_KIT_OVERWRITE_BITBUCKET_PIPELINE=1 ./scripts/update-kit.sh
```

Allow running with tracked local changes:

```bash
UPDATE_KIT_ALLOW_DIRTY=1 ./scripts/update-kit.sh
```

Remove the existing `docker/` directory before copying the template version:

```bash
UPDATE_KIT_PRUNE_DOCKER=1 ./scripts/update-kit.sh
```

Use another template source or branch:

```bash
TEMPLATE_REPO=https://github.com/m49n/docker_october.git TEMPLATE_REF=main ./scripts/update-kit.sh
```

## Windows

Run the script from Git Bash or WSL:

```bash
cd /d/OSPanel/domains/example.loc
./scripts/update-kit.sh
```

If you use PowerShell only, copy the kit files manually and review `git diff` before committing.
