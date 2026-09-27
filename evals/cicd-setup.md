# Eval Runbook — cicd-setup

## Fixture

`evals/fixtures/mysql-horizon-vite/` — MySQL + Horizon + Vite, no tenancy, no PHPStan, no second server. The modal/common case across the projects this skill was built from.

## How to run

```bash
cp -r evals/fixtures/mysql-horizon-vite "/tmp/cicd-setup-eval-$(date +%s)"
cd /tmp/cicd-setup-eval-*
git init -q
```

Then, in a Claude Code session started from that directory, prompt:

> Set up CI/CD for this project. Domain: eval.test, server IP: 203.0.113.10, deploy path default, port 8091, GitHub owner godiah, no second server, this app owns its schema, no PROD_READY guard.

(Answers are pre-filled so the run checks detection + generation, not the Step 1 questioning UX.)

## Expected behaviors

- [ ] Detects `PHP_VERSION=8.4`, `HAS_HORIZON=true`, `HAS_VITE=true`, `DB_TYPE=mysql`, `HAS_TENANCY=false`, `HAS_PHPSTAN=false`
- [ ] Generates every file listed in the skill's "What this skill produces"
- [ ] `.github/workflows/ci.yml`/`cd.yml` pin the reusable-workflow `@vX.Y.Z` tag matching the latest tag in `godiah/laravel-cicd` at generation time, not whatever's hardcoded in the caller template on disk — check the caller template's pin isn't stale before trusting it (this is exactly what was wrong on 2026-09-27: templates pinned `@v1.0.3`, three fixes behind)
- [ ] `docker-compose.prod.yaml` includes a `horizon` service with `healthcheck: disable: true`, and no `postgres` service
- [ ] `Dockerfile.production`'s Node build stage is actually **activated** (uncommented `FROM node:22-alpine AS assets` stage + `COPY --from=assets ...`), not left as a dead commented block — this is the near-miss found on the first real run of this eval: it's invisible to a `{{PLACEHOLDER}}` grep since the block uses bracket-comment markers, not tokens
- [ ] `.github/workflows/ci.yml` includes npm steps; does NOT include a separate PHPStan `analyse` job
- [ ] `.github/workflows/cd.yml`'s deploy step pulls/restarts `horizon`, not just `app nginx scheduler`
- [ ] No `{{PLACEHOLDER}}` and no leftover `[..._BLOCK]` marker comment left in any generated file
- [ ] Step 3.5's validation commands are actually run and their results reported, not silently skipped
- [ ] Recognizes the fixture's `composer.json` already has `lint`/`format`/`test` scripts — doesn't duplicate or ask about them

## Must not

- [ ] Must not run `php artisan migrate` or any command against a real database — this fixture has none
- [ ] Must not silently overwrite files on a second run if a `docker-compose.prod.yaml` already exists — should flag this per the skill's "Do not use this skill when" / "Destructive operations" sections
- [ ] Must not fabricate `PROD_SERVER_IP`/`PROD_DOMAIN` — must use exactly the values given in the prompt
- [ ] Must not leave a throwaway `.env` (created only for verification command 1) sitting in the generated project afterward
- [ ] Must not leave a `Dockerfile.production` Node stage commented-out while claiming Vite support is wired up — verify the container would actually build assets, don't just check the file exists

## Verification commands

Run inside the eval scratch directory after generation — these are the exact, corrected commands from the skill's own Step 3.5 (the originally-written versions of checks 1 and 2 both failed on the first real run of this eval, for reasons unrelated to the generated files: no `.env` yet, and nginx resolving the `app` upstream hostname outside a running compose network):

```bash
CREATED_ENV=false
if [ ! -f .env ]; then
  printf 'DB_PASSWORD=eval\nDB_DATABASE=eval\nDB_USERNAME=eval\n' > .env
  CREATED_ENV=true
fi

docker compose -f docker-compose.prod.yaml config --quiet && echo OK
[ "$CREATED_ENV" = true ] && rm -f .env

docker run --rm --add-host=app:127.0.0.1 \
  -v "$(pwd)/docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "$(pwd)/docker/nginx/conf.d:/etc/nginx/conf.d:ro" \
  nginx:1.27-alpine nginx -t

grep -rn '{{[A-Z_]*}}' . \
  --include='*.yml' --include='*.yaml' --include='Dockerfile.production' \
  && echo "FAIL: leftover placeholder" || echo OK

grep -rn '\[[A-Z_]*_BLOCK\]' . && echo "FAIL: leftover block marker" || echo OK
```

## When this fails

Fix the template/skill in `~/laravel-cicd`, re-run `install.sh`, re-run this eval from a fresh scratch copy of the fixture before pushing.

## Run log

- **2026-09-27, first run:** found and fixed a stale caller-template pin (`@v1.0.3` → `@v1.0.6`, three real fixes behind — see repo commit `f664d67`); found and fixed two bugs in Step 3.5's own validation commands (missing `.env`, unresolvable nginx upstream); clarified Step 3's Dockerfile/Compose instructions to describe the bracket-comment conditional-block mechanism instead of implying simple `{{PLACEHOLDER}}` substitution, since that mechanism isn't caught by a placeholder grep. All checks pass clean after fixes. Full narrative in `project-cicd-package` memory.
