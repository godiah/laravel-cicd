# Laravel CI/CD Templates

A reusable Claude Code skill and template library for setting up production-grade CI/CD pipelines for Laravel projects deployed to Docker on a VPS.

Built from patterns extracted across 6 production Laravel projects.

## What's Included

| File | Purpose |
|------|---------|
| `skill.md` | The `/cicd-setup` Claude Code skill — installed to `~/.claude/skills/` |
| `templates/workflows/ci.yml` | GitHub Actions CI: lint, audit, test, build-check, auto-merge |
| `templates/workflows/cd.yml` | GitHub Actions CD: GHCR push + SSH deploy |
| `templates/workflows/cd-production.yml` | Optional manual second-server promotion |
| `templates/Dockerfile.production` | Multi-stage Alpine build (composer → node → php-fpm → nginx) |
| `templates/docker-compose.prod.yaml` | Production stack with healthchecks and named networks |
| `templates/.dockerignore` | Standard Docker ignore file |
| `templates/docker/php/php.ini` | Production PHP config (opcache, memory, upload limits) |
| `templates/docker/php/www.conf` | PHP-FPM pool config |
| `templates/docker/php/docker-entrypoint.sh` | Container entrypoint (volume permission fix) |
| `templates/docker/nginx/nginx.conf` | Main nginx config (gzip, security headers) |
| `templates/docker/nginx/conf.d/app.conf` | Laravel app nginx location blocks |
| `templates/setup/server-setup.sh` | One-shot VPS bootstrap script |
| `templates/setup/nginx-host.conf` | Host nginx TLS termination config |
| `templates/setup/secrets-reference.md` | GitHub secrets documentation |
| `templates/setup/branch-protection.md` | GitHub branch protection rules |

## Installation

```bash
git clone git@github.com:godiah/laravel-cicd.git ~/laravel-cicd
bash ~/laravel-cicd/install.sh
```

This installs the skill to `~/.claude/skills/cicd-setup.md` and all templates to `~/.claude/cicd-templates/`.

## Updating

When templates or the skill are improved, pull and re-install:

```bash
bash ~/laravel-cicd/update.sh
```

## Usage

In any Laravel project directory, open Claude Code and run:

```
/cicd-setup
```

Claude will:
1. Detect your project's stack (PHP version, MySQL vs PostgreSQL, Horizon, Vite, multi-tenancy, etc.)
2. Ask a few questions (domain, server IP, port, GitHub username)
3. Generate all CI/CD files adapted for your specific project
4. Print a checklist of GitHub secrets to configure and server steps to complete

## What Gets Generated Per Project

```
.github/
  workflows/
    ci.yml                 # lint → audit → test → build-check → auto-merge
    cd.yml                 # build Docker images → push GHCR → SSH deploy
    cd-production.yml      # [optional] manual second-server promotion
  setup/
    server-setup.sh        # one-shot VPS bootstrap
    nginx-host.conf        # host nginx TLS + proxy config
    secrets-reference.md   # what GitHub secrets to set
    branch-protection.md   # branch protection rules
Dockerfile.production      # multi-stage Alpine
docker-compose.prod.yaml   # production Docker Compose
.dockerignore
docker/
  php/
    php.ini
    www.conf
    docker-entrypoint.sh
  nginx/
    nginx.conf
    conf.d/app.conf
```

## Branch Strategy

```
develop / feature/** → CI → auto-merge → main → CD → VPS
```

## Supported Variations

The skill detects and adapts for:
- **PHP version** — 8.3, 8.4, 8.5+
- **Database** — MySQL 8.4 or PostgreSQL 16
- **Queue workers** — Laravel Horizon or simple queue:work
- **Frontend** — Vite (adds node stage to Dockerfile + npm steps to CI) or API-only
- **Multi-tenancy** — Stancl Tenancy (adds `tenants:migrate` to deploy)
- **Static analysis** — PHPStan/Larastan (adds separate analyse job to CI)
- **Schema ownership** — can skip migrations for apps sharing a DB with a schema-owner app
- **Second server** — optional `cd-production.yml` for promoting a build to a second VPS
- **Deploy guard** — `PROD_READY=true` variable gates deploy until server is provisioned

## Required GitHub Secrets (always)

| Secret | Purpose |
|--------|---------|
| `GH_PAT` | PAT with `repo` scope — used by auto-merge to push to main |
| `GHCR_PULL_TOKEN` | PAT with `read:packages` scope — used by VPS to pull images |
| `PROD_SSH_HOST` | VPS IP address |
| `PROD_SSH_USER` | SSH user on the VPS |
| `PROD_SSH_KEY` | ED25519 private key |
