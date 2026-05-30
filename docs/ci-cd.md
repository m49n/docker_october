# CI/CD Notes

## Required Secrets

- `COMPOSER_AUTH`: JSON Composer auth for October Gateway
- Registry username/password or cloud registry token
- Production SSH/deploy token, if deploy is triggered from CI

Example `COMPOSER_AUTH` value:

```json
{"http-basic":{"gateway.octobercms.com":{"username":"account@example.com","password":"october-license-key"}}}
```

## GitHub Actions Sketch

```yaml
name: Build production images

on:
  push:
    branches:
      - main

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      IMAGE_TAG: ${{ github.sha }}
      APP_IMAGE: ghcr.io/example/october-app
      NGINX_IMAGE: ghcr.io/example/october-nginx
    steps:
      - uses: actions/checkout@v4

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/setup-buildx-action@v3

      - name: Build app image
        run: |
          docker build \
            --secret id=composer_auth,env=COMPOSER_AUTH \
            --target app \
            -t "$APP_IMAGE:$IMAGE_TAG" .
        env:
          COMPOSER_AUTH: ${{ secrets.COMPOSER_AUTH }}

      - name: Build nginx image
        run: |
          docker build \
            --target nginx \
            -t "$NGINX_IMAGE:$IMAGE_TAG" .

      - name: Push images
        run: |
          docker push "$APP_IMAGE:$IMAGE_TAG"
          docker push "$NGINX_IMAGE:$IMAGE_TAG"
```

## Deploy Order

1. Build `app` image.
2. Build `nginx` image from the same source revision.
3. Push both images.
4. Pull on the server.
5. Run `./scripts/deploy.sh` on the server.

The helper script runs `october:migrate --force` explicitly, signals queue and scheduler workers, then updates containers.
