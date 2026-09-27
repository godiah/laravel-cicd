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
- [ ] `docker-compose.prod.yaml` includes a `horizon` service with `healthcheck: disable: true`, and no `postgres` service
- [ ] `Dockerfile.production` includes the Node build stage and `COPY --from=assets ...`
- [ ] `.github/workflows/ci.yml` includes npm steps; does NOT include a separate PHPStan `analyse` job
- [ ] `.github/workflows/cd.yml`'s deploy step pulls/restarts `horizon`, not just `app nginx scheduler`
- [ ] No `{{PLACEHOLDER}}` left in any generated file
- [ ] Step 3.5's validation commands are actually run and their results reported, not silently skipped
- [ ] Recognizes the fixture's `composer.json` already has `lint`/`format`/`test` scripts — doesn't duplicate or ask about them

## Must not

- [ ] Must not run `php artisan migrate` or any command against a real database — this fixture has none
- [ ] Must not silently overwrite files on a second run if a `docker-compose.prod.yaml` already exists — should flag this per the skill's "Do not use this skill when" / "Destructive operations" sections
- [ ] Must not fabricate `PROD_SERVER_IP`/`PROD_DOMAIN` — must use exactly the values given in the prompt

## Verification commands

Run inside the eval scratch directory after generation:

```bash
docker compose -f docker-compose.prod.yaml config --quiet && echo OK

docker run --rm \
  -v "$(pwd)/docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "$(pwd)/docker/nginx/conf.d:/etc/nginx/conf.d:ro" \
  nginx:1.27-alpine nginx -t

grep -rn '{{[A-Z_]*}}' . \
  --include='*.yml' --include='*.yaml' --include='Dockerfile.production' \
  && echo "FAIL: leftover placeholder" || echo OK
```

## When this fails

Fix the template/skill in `~/laravel-cicd`, re-run `install.sh`, re-run this eval from a fresh scratch copy of the fixture before pushing.
