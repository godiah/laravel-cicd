# CI/CD Setup Skill

## TRIGGER
Invoke this skill when the user asks to "set up CI/CD", "add CI/CD", "create pipelines", or "configure GitHub Actions" for a Laravel project. This is a full-project operation — read the project before generating anything.

## WHAT THIS SKILL PRODUCES
For any Laravel PHP project on a VPS with Docker, this skill generates:
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

Templates live at: `~/.claude/cicd-templates/`

---

## STEP 1 — DETECT PROJECT PROPERTIES

Before writing a single file, read these sources and build a properties map:

### From `composer.json`:
- `PHP_VERSION` — `require.php` field, strip the `^` (e.g. `^8.4` → `8.4`)
- `HAS_HORIZON` — `true` if `laravel/horizon` is in require or require-dev
- `HAS_PHPSTAN` — `true` if `phpstan/phpstan` or `larastan/larastan` is present
- `HAS_TENANCY` — `true` if `stancl/tenancy` is present
- `HAS_SWAGGER` — `true` if `darkaonline/l5-swagger` is present
- `DB_SEED_COMMAND` — check if `db:seed` is used (safe if seeders use updateOrCreate/firstOrCreate)

### From `package.json` or vite.config.js:
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

## STEP 2 — DERIVE COMPUTED VALUES

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

## STEP 3 — GENERATE FILES

Use the templates in `~/.claude/cicd-templates/` as the starting point. Copy each template and substitute all `{{PLACEHOLDER}}` values. Do NOT leave any `{{PLACEHOLDER}}` in the final files.

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

### 3. `.github/workflows/cd.yml`
Use `~/.claude/cicd-templates/workflows/cd.yml` as base.

Key substitutions:
- `{{APP_IMAGE}}` — GHCR app image URL
- `{{NGINX_IMAGE}}` — GHCR nginx image URL
- `{{PROD_DOMAIN}}` — production URL
- `{{DEPLOY_PATH}}` — `/opt/{{APP_NAME_SLUG}}`
- `{{EXTRA_MIGRATE_CD}}` — tenant migrate or empty
- `{{HORIZON_DRAIN_BLOCK}}` — drain + restart block
- `{{PROD_READY_CONDITION}}` — `if: vars.PROD_READY == 'true'` or empty
- `{{DOCKERFILE_NAME}}` — `Dockerfile.production` or `Dockerfile`

### 4. `.github/workflows/cd-production.yml` (only if SECOND_SERVER == yes)
Use `~/.claude/cicd-templates/workflows/cd-production.yml` as base.

### 5. `Dockerfile.production`
Use `~/.claude/cicd-templates/Dockerfile.production` as base.

Key substitutions:
- `{{PHP_VERSION}}` — e.g. `8.4`
- `{{DB_PHP_EXT}}` — `pdo_mysql` or `pdo_pgsql pgsql`
- `{{NODE_STAGE}}` — node builder stage if HAS_VITE, else empty
- `{{COPY_BUILD_ASSETS}}` — copy built assets if HAS_VITE
- `{{APP_LABEL}}` — APP_NAME

### 6. `docker-compose.prod.yaml`
Use `~/.claude/cicd-templates/docker-compose.prod.yaml` as base.

Key substitutions:
- `{{APP_IMAGE}}` — full GHCR app image
- `{{NGINX_IMAGE}}` — full GHCR nginx image
- `{{PROD_PORT}}` — host port for nginx (e.g. 8080)
- `{{DB_SERVICE_BLOCK}}` — mysql or postgres service definition
- `{{DB_VOLUME_NAME}}` — `mysql_data` or `postgres_data`
- `{{NETWORK_NAME}}` — `{{APP_NAME_SLUG}}-prod`
- `{{APP_NAME_SLUG}}` — for network and volume names

### 7. `.dockerignore`
Copy `~/.claude/cicd-templates/.dockerignore` verbatim.

### 8. `docker/php/php.ini`
Copy `~/.claude/cicd-templates/docker/php/php.ini` verbatim.

### 9. `docker/php/www.conf`
Copy `~/.claude/cicd-templates/docker/php/www.conf` verbatim.

### 10. `docker/php/docker-entrypoint.sh`
Copy `~/.claude/cicd-templates/docker/php/docker-entrypoint.sh` verbatim.

### 11. `docker/nginx/nginx.conf`
Copy `~/.claude/cicd-templates/docker/nginx/nginx.conf` verbatim.

### 12. `docker/nginx/conf.d/app.conf`
Copy `~/.claude/cicd-templates/docker/nginx/conf.d/app.conf` verbatim.

### 13. `.github/setup/server-setup.sh`
Use `~/.claude/cicd-templates/setup/server-setup.sh` as base.

Key substitutions:
- `{{APP_NAME_SLUG}}` — project name slug
- `{{DEPLOY_PATH}}` — `/opt/{{APP_NAME_SLUG}}`
- `{{GITHUB_REPO_OWNER}}` — GitHub username
- `{{PROD_DOMAIN}}` — production domain
- `{{PROD_PORT}}` — host port

### 14. `.github/setup/nginx-host.conf`
Use `~/.claude/cicd-templates/setup/nginx-host.conf` as base.

Substitutions: `{{PROD_DOMAIN}}`, `{{PROD_PORT}}`

### 15. `.github/secrets-reference.md`
Use `~/.claude/cicd-templates/setup/secrets-reference.md` as base.

Substitutions: `{{APP_NAME}}`, `{{PROD_DOMAIN}}`, `{{PROD_SERVER_IP}}`

Add any project-specific secrets detected (e.g. if M-Pesa keys found in .env.example).

### 16. `.github/branch-protection.md`
Copy `~/.claude/cicd-templates/setup/branch-protection.md`.
Update the required status checks to match the actual CI job names generated.

---

## STEP 4 — VERIFY `composer.json` SCRIPTS

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

## STEP 5 — POST-GENERATION CHECKLIST

After generating all files, print this checklist for the user:

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

## DECISION GUIDES

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

## COMMON PITFALLS TO AVOID

1. **Never use `--no-ff` merge in auto-merge when the branch is already fast-forwardable** — use `--no-ff` for develop→main (preserves branch history) but either works

2. **The `--env-file .image-tag.env` trick** — always write `APP_IMAGE_TAG=sha-${SHORT_SHA:0:7}` to `.image-tag.env` before compose commands; prevents race conditions between concurrent deploys

3. **Run caches in a one-off container BEFORE starting the service** (sms-platform pattern) OR exec into the container AFTER it's healthy (pokeapay pattern) — both work, but never mix them mid-deploy

4. **Horizon healthcheck must be disabled** — `healthcheck: disable: true` on the horizon service; it's a queue worker with no HTTP port

5. **Network naming** — always set an explicit `networks.default.name` in docker-compose.prod.yaml to avoid Docker auto-naming conflicts when multiple projects run on the same host

6. **Alpine sh** — doesn't support brace expansion `{a,b,c}`; use explicit paths in RUN commands

7. **PHP extensions in the vendor stage** — use `--ignore-platform-reqs` in the composer stage; install real extensions in the PHP-FPM stage

8. **The `</dev/null` heredoc drain** (SaccoMs lesson) — when using SSH heredoc with `docker compose exec -T`, pass `</dev/null` to each exec command to prevent the heredoc stdin from being consumed
