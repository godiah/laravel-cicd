---
name: cicd-setup
description: Use this skill when the user asks to "set up CI/CD", "add CI/CD", "create pipelines", "configure GitHub Actions", or "deploy this to production" for a Laravel project on a Docker/VPS stack. Full-project operation — detects PHP version, database, queue driver, frontend build tool, and multi-tenancy from the project's own files, then generates GitHub Actions workflows, a production Dockerfile, Compose stack, nginx/PHP config, and server-provisioning scripts adapted to what it found. Read the project before generating anything.
---

# CI/CD Setup

## Overview

For any Laravel PHP project on a VPS with Docker, this skill generates a full CI/CD pipeline: GitHub Actions workflows (lint → test → build → deploy), a production multi-stage Dockerfile, a Compose stack with healthchecks, nginx/PHP config, and server-provisioning scripts — all adapted to the specific project's stack rather than a generic template dump.

Templates live at: `~/.claude/cicd-templates/`

## When to use this skill

- "set up CI/CD" / "add CI/CD" / "create pipelines" / "configure GitHub Actions" for a Laravel project
- "deploy this to production" when no pipeline exists yet
- Immediately after `new-project` finishes scaffolding a new Laravel app

## Do not use this skill when

- CI/CD already exists and the ask is a targeted change (e.g. "add a PHPStan job", "bump the PHP version") — edit the existing workflow/Dockerfile directly. Regenerating from templates overwrites manual edits already made on top of them.
- The project isn't Laravel, or isn't deploying to a Docker container on a VPS (serverless, shared hosting, Vercel, etc.) — every template here assumes Docker Compose + GHCR + SSH deploy.
- The user is asking to actually *run* a deploy, a migration, or a rollback — that's execution, not setup. Use `rollback` for rollbacks; run deploy/migrate commands directly, this skill only generates files.

## What this skill produces

- `.github/workflows/ci.yml` — lint, audit, test, build-check, auto-merge
- `.github/workflows/cd.yml` — Docker build → GHCR push → SSH deploy
- `.github/workflows/cd-production.yml` — optional manual second-server promotion
- `Dockerfile.production` — multi-stage Alpine build
- `docker-compose.prod.yaml` — production service stack
- `.dockerignore`
- `docker/php/php.ini`, `www.conf`, `docker-entrypoint.sh`
- `docker/nginx/nginx.conf`, `docker/nginx/conf.d/app.conf`
- `.github/setup/server-setup.sh`
- `.github/setup/nginx-host.conf`
- `.github/secrets-reference.md`
- `.github/branch-protection.md`

---

## Step 1 — Detect project properties

Before writing a single file, read these sources and build a properties map:

### From `composer.json`:
- `PHP_VERSION` — `require.php` field, strip the `^` (e.g. `^8.4` → `8.4`)
- `HAS_HORIZON` — `true` if `laravel/horizon` is in require or require-dev
- `HAS_PHPSTAN` — `true` if `phpstan/phpstan` or `larastan/larastan` is present
- `HAS_TENANCY` — `true` if `stancl/tenancy` is present
- `HAS_SWAGGER` — `true` if `darkaonline/l5-swagger` is present
- `DB_SEED_COMMAND` — check if `db:seed` is used (safe if seeders use updateOrCreate/firstOrCreate)

### From `package.json` or `vite.config.js`:
- `HAS_VITE` — `true` if `vite.config.js` exists OR `vite` is in devDependencies

### From `.env.example`:
- `DB_TYPE` — `mysql` if `DB_CONNECTION=mysql`, `pgsql` if `DB_CONNECTION=pgsql`
- `APP_NAME_SLUG` — lowercase, hyphenated version of `APP_NAME` value
- `HAS_REDIS` — `true` if `REDIS_HOST` key exists (almost always true)

### Ask the user:
- `PROD_DOMAIN` — production domain (e.g. `api.myapp.com`)
- `PROD_SERVER_IP` — VPS IP address
- `PROD_DEPLOY_PATH` — path on server (default: `/opt/{{APP_NAME_SLUG}}`)
- `PROD_PORT` — port nginx binds to on host (default `8080`; must not conflict with other apps on same server)
- `GITHUB_REPO_OWNER` — GitHub username/org (e.g. `godiah`)
- `SECOND_SERVER` — does this project need a cd-production.yml for a second server? (yes/no)
- `SCHEMA_OWNER` — for shared-database multi-app setups, does this app own migrations? (yes/skip/na)
- `PROD_READY_GUARD` — should deploy be gated on a `PROD_READY=true` variable until the server is provisioned? (yes/no)

---

## Step 2 — Derive computed values

```
APP_IMAGE    = ghcr.io/{{GITHUB_REPO_OWNER}}/{{APP_NAME_SLUG}}
NGINX_IMAGE  = ghcr.io/{{GITHUB_REPO_OWNER}}/{{APP_NAME_SLUG}}

# Database
if DB_TYPE == mysql:
  DB_SERVICE_IMAGE    = mysql:8.4
  DB_SERVICE_NAME     = mysql
  DB_PHP_EXTENSIONS   = pdo_mysql
  DB_HEALTHCHECK      = mysqladmin ping -ppassword
  DB_WAIT_ENV         = MYSQL_ROOT_PASSWORD: password\n  MYSQL_DATABASE: testing
  DB_CI_ENV           = DB_HOST: 127.0.0.1\n  DB_PASSWORD: password
  DB_CI_SED_PATCH     = (patch DB_CONNECTION=mysql, DB_HOST=127.0.0.1, DB_PORT=3306, DB_USERNAME=root, DB_PASSWORD=password)
  DB_TEST_OPTS        = ""   (DB_PASSWORD goes into job-level env)
else (pgsql):
  DB_SERVICE_IMAGE    = postgres:16.3-alpine
  DB_SERVICE_NAME     = postgres
  DB_PHP_EXTENSIONS   = pdo_pgsql pgsql
  DB_HEALTHCHECK      = pg_isready -U postgres -d testing
  DB_WAIT_ENV         = POSTGRES_DB: testing\n  POSTGRES_USER: postgres\n  POSTGRES_HOST_AUTH_METHOD: trust
  DB_CI_ENV           = (set as step env: DB_CONNECTION, DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME)
  DB_TEST_OPTS        = (expose via env block on run step)

# Tenancy
if HAS_TENANCY:
  EXTRA_MIGRATE_CI    = "php artisan tenants:migrate --force"
  EXTRA_MIGRATE_CD    = "run --rm --no-deps app php artisan tenants:migrate --force"
  EXTRA_MIGRATE_NOTES = "# Tenant migrations across all provisioned tenants"
else:
  EXTRA_MIGRATE_CI    = ""
  EXTRA_MIGRATE_CD    = ""

# Horizon
if HAS_HORIZON:
  HORIZON_DRAIN_BLOCK = (horizon:terminate + poll loop + restart horizon)
else:
  HORIZON_DRAIN_BLOCK = (simple queue:restart if queue workers present, else empty)

# Frontend
if HAS_VITE:
  NODE_STAGE_DOCKERFILE = (stage 2 node build)
  CI_NPM_STEPS          = (npm ci + npm run build steps in test job)
  DOCKERFILE_COPY_BUILD  = COPY --from=assets /app/public/build ./public/build
else:
  NODE_STAGE_DOCKERFILE = ""
  CI_NPM_STEPS          = ""
  DOCKERFILE_COPY_BUILD = ""
```

---

## Step 3 — Generate files

Use the templates in `~/.claude/cicd-templates/` as the starting point. Copy each template and substitute all `{{PLACEHOLDER}}` values. Do NOT leave any `{{PLACEHOLDER}}` in the final files — Step 3.5 checks for this.

**Preferred approach — reusable workflows (thin callers):**
Use `ci-caller.yml` and `cd-caller.yml` templates. These delegate all logic to the central reusable workflows in `godiah/laravel-cicd`. When the central workflows improve, all projects get the update automatically. The caller files are tiny (~15–20 lines each).

**Fallback — standalone workflows:**
Use `ci-standalone.yml` and `cd-standalone.yml` if the project cannot call `godiah/laravel-cicd` (e.g. different GitHub org, or the project needs non-standard customization). The standalone files are self-contained and fully parameterized.

Work through files in this order:

### 1. Create directory structure
```bash
mkdir -p .github/workflows .github/setup docker/php docker/nginx/conf.d
```

### 2. `.github/workflows/ci.yml` (caller — preferred)
Use `~/.claude/cicd-templates/workflows/ci-caller.yml` as base.

Key substitutions:
- `{{PHP_VERSION}}` — from detection (e.g. `8.4`)
- `{{DB_TYPE}}` — `mysql` or `pgsql`
- `{{HAS_VITE}}` — `true` or `false`
- `{{HAS_PHPSTAN}}` — `true` or `false`
- `{{HAS_TENANCY}}` — `true` or `false`
- `{{APP_NAME_SLUG}}` — hyphenated app name (e.g. `pokeapay-donations`)

### 3. `.github/workflows/cd.yml` (caller — preferred)
Use `~/.claude/cicd-templates/workflows/cd-caller.yml` as base.

Key substitutions:
- `{{GITHUB_REPO_OWNER}}` — GitHub username (e.g. `godiah`)
- `{{APP_NAME_SLUG}}` — hyphenated app name
- `{{DEPLOY_PATH}}` — `/opt/{{APP_NAME_SLUG}}`
- `{{PROD_DOMAIN}}` — production domain
- `{{DB_SERVICE_NAME}}` — `mysql` or `postgres`
- `{{HAS_HORIZON}}` — `true` or `false`
- `{{HAS_TENANCY}}` — `true` or `false`
- `{{SKIP_MIGRATE}}` — `true` if this app does NOT own the schema
- `{{HAS_SEED}}` — `true` if project has idempotent seeders

### [ALTERNATIVE] `.github/workflows/ci.yml` (standalone)
Use `~/.claude/cicd-templates/workflows/ci-standalone.yml` only if reusable workflow approach is not viable.

Key substitutions:
- `{{PHP_VERSION}}` — from detection
- `{{DB_SERVICE_BLOCK}}` — mysql or pgsql service definition
- `{{DB_CI_ENV_BLOCK}}` — job-level env vars for DB connection
- `{{DB_ENV_PATCH_STEPS}}` — sed commands to patch .env
- `{{NPM_STEPS}}` — empty string or npm ci + build steps
- `{{EXTRA_MIGRATE}}` — tenants:migrate step or empty
- `{{BUILD_CHECK_IMAGE_NAME}}` — `{{APP_NAME_SLUG}}-build-check:ci`
- `{{PHPSTAN_JOB}}` — full analyse job block if HAS_PHPSTAN, else empty
- `{{CI_NEEDS}}` — `[lint, audit, test, build-check]` or `[test, build-check]`

### 4. `Dockerfile.production`
Use `~/.claude/cicd-templates/Dockerfile.production` as base.

Key substitutions:
- `{{PHP_VERSION}}` — e.g. `8.4`
- `{{DB_PHP_EXT}}` — `pdo_mysql` or `pdo_pgsql pgsql`
- `{{NODE_STAGE}}` — node builder stage if HAS_VITE, else empty
- `{{COPY_BUILD_ASSETS}}` — copy built assets if HAS_VITE
- `{{APP_LABEL}}` — APP_NAME

### 5. `docker-compose.prod.yaml`
Use `~/.claude/cicd-templates/docker-compose.prod.yaml` as base.

Key substitutions:
- `{{APP_IMAGE}}` — full GHCR app image
- `{{NGINX_IMAGE}}` — full GHCR nginx image
- `{{PROD_PORT}}` — host port for nginx (e.g. 8080)
- `{{DB_SERVICE_BLOCK}}` — mysql or postgres service definition
- `{{DB_VOLUME_NAME}}` — `mysql_data` or `postgres_data`
- `{{NETWORK_NAME}}` — `{{APP_NAME_SLUG}}-prod`
- `{{APP_NAME_SLUG}}` — for network and volume names

### 6. `.dockerignore`, PHP config, nginx config
Copy verbatim from `~/.claude/cicd-templates/`:
- `.dockerignore`
- `docker/php/php.ini`, `docker/php/www.conf`, `docker/php/docker-entrypoint.sh`
- `docker/nginx/nginx.conf`, `docker/nginx/conf.d/app.conf`

### 7. `.github/setup/server-setup.sh`
Use `~/.claude/cicd-templates/setup/server-setup.sh` as base.

Key substitutions: `{{APP_NAME_SLUG}}`, `{{DEPLOY_PATH}}`, `{{GITHUB_REPO_OWNER}}`, `{{PROD_DOMAIN}}`, `{{PROD_PORT}}`

### 8. `.github/setup/nginx-host.conf`
Use `~/.claude/cicd-templates/setup/nginx-host.conf` as base. Substitutions: `{{PROD_DOMAIN}}`, `{{PROD_PORT}}`

### 9. `.github/secrets-reference.md`
Use `~/.claude/cicd-templates/setup/secrets-reference.md` as base. Substitutions: `{{APP_NAME}}`, `{{PROD_DOMAIN}}`, `{{PROD_SERVER_IP}}`. Add any project-specific secrets detected (e.g. if M-Pesa keys found in .env.example).

### 10. `.github/branch-protection.md`
Copy `~/.claude/cicd-templates/setup/branch-protection.md`. Update the required status checks to match the actual CI job names generated.

### 11. `cd-production.yml` (only if SECOND_SERVER == yes)
Use `~/.claude/cicd-templates/workflows/cd-production.yml` as base.

---

## Step 3.5 — Validate generated files

**Do this every time, before Step 4.** Every real bug found in this template's history — nginx 404s on dynamic routes, a missing storage volume, a healthcheck bound to the wrong address, an invalid TLS block, a missing `storage:link` — was only caught by a client's live production deploy, never before it. That's the pattern to break. Run these checks against what you just generated and fix anything that fails before presenting the Step 5 checklist:

```bash
# 1. Compose file is syntactically valid (works without real secrets present)
docker compose -f docker-compose.prod.yaml config --quiet \
  && echo "OK: compose config valid" || echo "FAIL: compose config invalid"

# 2. Nginx config is valid — check it in a throwaway container, not by eye
docker run --rm \
  -v "$(pwd)/docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "$(pwd)/docker/nginx/conf.d:/etc/nginx/conf.d:ro" \
  nginx:1.27-alpine nginx -t

# 3. No leftover template placeholders anywhere generated
grep -rn '{{[A-Z_]*}}' .github/ docker/ Dockerfile.production docker-compose.prod.yaml 2>/dev/null \
  && echo "FAIL: unresolved placeholders above" || echo "OK: no leftover placeholders"

# 4. GitHub Actions workflow syntax, if actionlint is available
command -v actionlint >/dev/null 2>&1 \
  && actionlint .github/workflows/*.yml \
  || echo "actionlint not installed — skip, don't block on it"
```

If check 1 or 2 fails, or check 3 finds a leftover placeholder, fix the generated file and re-run before moving on. Do not hand the user a "next steps" checklist for files that don't pass their own syntax check.

---

## Step 4 — Verify `composer.json` scripts

Check that `composer.json` has the scripts expected by CI. If missing, add them and tell the user:

```json
"scripts": {
    "lint": "vendor/bin/pint --test",
    "format": "vendor/bin/pint",
    "test": "php artisan test",
    "analyse": "vendor/bin/phpstan analyse"   // only if HAS_PHPSTAN
}
```

---

## Step 5 — Post-generation checklist

After generating and validating all files, print this checklist for the user:

```
✅ Files generated in: [list all files created]

📋 NEXT STEPS — must complete before first deploy:

GitHub Setup:
  □ Push the branch and open a PR (or push to develop to trigger CI)
  □ Settings → Secrets → add: GH_PAT, GHCR_PULL_TOKEN, PROD_SSH_HOST, PROD_SSH_USER, PROD_SSH_KEY
  □ Settings → Variables → add: PROD_READY=true (after server is provisioned)
  □ Settings → Branches → set branch protection on main (see .github/branch-protection.md)
  □ Settings → Packages → ensure {{APP_NAME_SLUG}} package is visible (auto-created on first push)

Server Provisioning:
  □ SCP or manually create: {{DEPLOY_PATH}}/.env (from .env.production.example)
  □ Run: bash .github/setup/server-setup.sh
  □ Verify: curl -si https://{{PROD_DOMAIN}}/up

.env.production.example:
  □ Create .env.production.example from .env.example with production-safe defaults (no real secrets)
  □ The real .env lives on the server only — never committed

Dockerfile check:
  □ Confirm docker/php/php.ini settings suit the app (memory_limit, upload_max_filesize)
  □ Confirm docker/nginx/conf.d/app.conf client_max_body_size suits file upload requirements
```

---

## Destructive operations

State exactly what will happen and get explicit confirmation before any of the following — never as a side effect of a larger "just set it all up" request:

- **Running `php artisan migrate` or `tenants:migrate` against a production database** — even a purely additive, backward-compatible migration. This project's checkout points straight at production with no staging tier; confirm as its own explicit step every time, not folded into a bigger task.
- **`docker compose -f docker-compose.prod.yaml down -v` or anything with `--volumes`/`docker volume rm`** — irreversibly deletes the `mysql_data`/`postgres_data`/`redis_data`/`storage` named volumes. If the goal is only to restart services, use `down` (no `-v`) or `restart`.
- **Overwriting an existing `.env`, `docker-compose.prod.yaml`, or nginx config on the server** that isn't obviously a first-time setup — diff against what's already there first.
- **Regenerating CI/CD files for a project that already has them** — confirm whether the intent is a full regenerate (loses any manual edits made on top of the templates) or a targeted patch to one file.

---

## Decision guides

### When to add PHPStan job vs inline lint
- Add separate `analyse` job if `larastan/larastan` ≥ v3 is in composer.json
- Otherwise keep Pint lint as part of the test job (simpler)

### MySQL vs PostgreSQL service in CI
- MySQL: use `ramsey/composer-install@v3`, job-level env vars for DB creds, sed-patch `.env`
- PostgreSQL: use `POSTGRES_HOST_AUTH_METHOD: trust` (no password needed for test DB)

### Cache strategy in CD
- Default: `type=gha,scope=app` for the app image, `type=gha,scope=nginx` for nginx
- If multiple projects share the same runner: use `type=registry` cache to avoid scope collisions

### Multi-tenant deploy order
- Always run `php artisan migrate --force` (central) BEFORE `php artisan tenants:migrate --force`
- The `--no-deps` flag is critical — don't restart DB containers mid-migration

### Horizon vs no-Horizon
- With Horizon: use the full drain loop (horizon:terminate → poll horizon:status → restart horizon service)
- Without Horizon: if project has queue workers, add `queue:restart` after app is healthy; if no queues, skip

### Schema ownership in shared-DB setups
- If this app is the schema owner: include `migrate` and `seed` steps
- If this app is NOT the schema owner (like sms-platform-client): skip migrate entirely, add a comment in cd.yml

---

## Common pitfalls to avoid

1. **Never use `--no-ff` merge in auto-merge when the branch is already fast-forwardable** — use `--no-ff` for develop→main (preserves branch history) but either works
2. **The `--env-file .image-tag.env` trick** — always write `APP_IMAGE_TAG=sha-${SHORT_SHA:0:7}` to `.image-tag.env` before compose commands; prevents race conditions between concurrent deploys
3. **Run caches in a one-off container BEFORE starting the service** (sms-platform pattern) OR exec into the container AFTER it's healthy (pokeapay pattern) — both work, but never mix them mid-deploy
4. **Horizon healthcheck must be disabled** — `healthcheck: disable: true` on the horizon service; it's a queue worker with no HTTP port
5. **Network naming** — always set an explicit `networks.default.name` in docker-compose.prod.yaml to avoid Docker auto-naming conflicts when multiple projects run on the same host
6. **Alpine sh** — doesn't support brace expansion `{a,b,c}`; use explicit paths in RUN commands
7. **PHP extensions in the vendor stage** — use `--ignore-platform-reqs` in the composer stage; install real extensions in the PHP-FPM stage
8. **The `</dev/null` heredoc drain** (SaccoMs lesson) — when using SSH heredoc with `docker compose exec -T`, pass `</dev/null` to each exec command to prevent the heredoc stdin from being consumed

---

## Related skills

- End-to-end new project scaffold (which calls this skill as its last step): `new-project`
- Roll back a bad production deployment: `rollback`
