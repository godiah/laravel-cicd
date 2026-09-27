---
name: rollback
description: Use this skill when the user says "rollback", "roll back", "revert deploy", "go back to previous version", or "undo deploy" for a project. Detects the project's GHCR image name, deploy path, and Horizon usage from its own docker-compose.prod.yaml and CD workflow, lets the user pick a target image tag, confirms explicitly, then executes the rollback over SSH and verifies the result.
---

# Rollback

## Overview

Rolls back a production deployment to a specific previous image tag: detect project info → pick a target tag → confirm → execute over SSH → verify.

## When to use this skill

- "rollback" / "roll back" / "revert deploy" / "go back to previous version" / "undo deploy" for a project

## Do not use this skill when

- The need is to ship a fix forward, not go back to an old image — that's a normal push-to-main CD deploy, not a rollback.
- The production schema is now incompatible with the older code and the real fix is a forward-compatible migration — rolling back the image alone won't resolve a schema mismatch. Say so explicitly instead of running the rollback anyway.
- No usable previous tag actually exists on GHCR (images past the 90-day retention window) — surface that limitation before attempting anything.

---

## Step 1 — Detect project info

Read these files to extract rollback parameters:

**From `docker-compose.prod.yaml`:**
- Image name pattern: `ghcr.io/OWNER/APP-SLUG:${APP_IMAGE_TAG:-latest}` → extract `OWNER` and `APP-SLUG`
- DB service name (mysql or postgres)
- Whether `horizon` service exists → `HAS_HORIZON`

**From `.github/workflows/cd-caller.yml` (or `cd.yml`):**
- `deploy-path` input value → `DEPLOY_PATH`
- `has-horizon` input → `HAS_HORIZON` (confirm)
- `prod-domain` input → `PROD_DOMAIN`

**From `.github/secrets-reference.md`:**
- `PROD_SSH_HOST` — server IP (listed as example value in the table)
- `PROD_SSH_USER` — SSH user

If any values can't be detected from files, ask the user.

---

## Step 2 — Determine target tag

Ask the user:
```
What would you like to roll back to?
  a) List available tags on the server (I'll SSH and show you)
  b) Specify a tag directly (e.g. sha-abc1234)
```

**If option (a) — list tags:**
Run via Bash:
```bash
ssh {{PROD_SSH_USER}}@{{PROD_SSH_HOST}} \
  "docker images ghcr.io/{{GITHUB_REPO_OWNER}}/{{APP_NAME_SLUG}} \
   --format '{{.Tag}}\t{{.CreatedSince}}' \
   | grep -v 'buildcache\|nginx\|none' \
   | sort -r \
   | head -15"
```

Present the output and ask: "Which tag should I deploy?"

**If option (b) — direct tag:**
Use the tag the user provides.

---

## Step 3 — Confirm before executing

Before running the rollback, confirm with the user:
```
Ready to roll back {{APP_NAME_SLUG}} to {{TARGET_TAG}} on {{PROD_DOMAIN}}.

This will:
  ✓ Pull image {{TARGET_TAG}} from GHCR
  ✓ Do a rolling restart of app → nginx
  {{#if HAS_HORIZON}}✓ Gracefully drain and restart Horizon workers{{/if}}
  ✓ Rebuild config/route/view/event caches from the old code
  ✗ Will NOT run migrate --rollback (schema changes are not reverted)

Proceed? (yes/no)
```

> **Important:** Always note that database migrations are NOT reversed. If the rolled-back code
> is incompatible with the current schema, the user needs to manually run `migrate:rollback` or
> the rollback may not fully fix the issue.

---

## Step 4 — Execute the rollback

Use the `rollback.sh` script if it exists on the server:
```bash
ssh {{PROD_SSH_USER}}@{{PROD_SSH_HOST}} \
  "cd {{DEPLOY_PATH}} && bash .github/setup/rollback.sh {{TARGET_TAG}}"
```

If `rollback.sh` is not on the server, run the steps inline:
```bash
ssh {{PROD_SSH_USER}}@{{PROD_SSH_HOST}} bash -s << 'ROLLBACK'
set -euo pipefail
cd {{DEPLOY_PATH}}

echo "APP_IMAGE_TAG={{TARGET_TAG}}" > .image-tag.env
COMPOSE="docker compose -f docker-compose.prod.yaml --env-file .image-tag.env"

PULL_SVCS="app nginx scheduler"
# Add horizon if has-horizon is true:
# PULL_SVCS="$PULL_SVCS horizon"
$COMPOSE pull $PULL_SVCS

$COMPOSE up -d --no-deps --wait {{DB_SERVICE_NAME}} redis
$COMPOSE up -d --no-deps --wait app

$COMPOSE exec -T app php artisan config:cache
$COMPOSE exec -T app php artisan route:cache
$COMPOSE exec -T app php artisan view:cache
$COMPOSE exec -T app php artisan event:cache

# Horizon drain (if applicable):
# $COMPOSE exec -T horizon php artisan horizon:terminate || true
# ... poll ...
# $COMPOSE up -d --no-deps horizon scheduler

$COMPOSE up -d --no-deps --wait nginx
docker image prune -f

echo "Rollback complete: {{TARGET_TAG}}"
ROLLBACK
```

---

## Step 5 — Verify

After the rollback completes, verify:
```bash
curl -si https://{{PROD_DOMAIN}}/up
```

Report the HTTP status and response to the user.

Also check container health:
```bash
ssh {{PROD_SSH_USER}}@{{PROD_SSH_HOST}} \
  "docker compose -f {{DEPLOY_PATH}}/docker-compose.prod.yaml ps"
```

---

## Edge cases

**"I don't have SSH access from this machine"**
Generate the rollback command for the user to run directly on the server:
```bash
cd {{DEPLOY_PATH}} && bash .github/setup/rollback.sh {{TARGET_TAG}}
```

**"The target image isn't on the server"**
The `rollback.sh` script handles this — it pulls from GHCR using `GHCR_PULL_TOKEN` from `.env`.
GHCR keeps images for 90 days by default. Very old tags may no longer exist.

**"Migrations were run with the new code and can't be rolled back"**
Warn the user explicitly. Rolling back the image won't undo schema changes.
If the old code is incompatible with the new schema, they need to either:
a) Run `php artisan migrate:rollback` (risky in production)
b) Write a forward-compatible fix and deploy that instead

**"The rollback itself fails"**
If the rollback breaks things, the last known-good state is still in `.image-tag.env`.
The user can also run: `docker compose -f docker-compose.prod.yaml up -d` to restart
whatever is currently configured.

---

## Destructive operations

This entire skill is a production-affecting operation by nature. Beyond the explicit Step 3 confirmation gate:

- **Never skip Step 3's confirmation**, even if the user's initial request already named a specific tag — restate what will happen and get an explicit yes before touching production.
- **Never run `migrate:rollback` on your own initiative** to "fix" a schema mismatch surfaced during rollback — that's a separate, riskier decision the user must make explicitly (see Edge cases above).
- **SSH commands here execute directly against production with no staging tier** — treat every command in Step 4 as live the first time it's run, not as something to iterate on against the real server.

---

## Related skills

- Generates the `docker-compose.prod.yaml` / `cd.yml` this skill reads: `cicd-setup`
- End-to-end new project scaffold: `new-project`
