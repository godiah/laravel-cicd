# New Laravel Project Skill

## TRIGGER
Invoke this skill when the user asks to "create a new Laravel project", "scaffold a new project", "start a new Laravel app", or "new project". This sets up a fully-configured Laravel project with all conventions wired from day one.

## WHAT THIS SKILL PRODUCES
- A new Laravel project with `composer create-project`
- Git initialized with `main` + `develop` branches
- CLAUDE.md with project context
- `.env.production.example` ready for server setup
- GitHub repo created (optional)
- CI/CD fully configured via `/cicd-setup`

---

## STEP 1 — GATHER PROJECT DETAILS

Ask the user these questions upfront (all in one message):

1. **Project name** — e.g. `my-app` (will be used as directory name and repo slug)
2. **Location** — where should it live?
   - `~/Intrepid/Projects/` (Intrepid work)
   - `~/MyProjects/` (personal projects)
   - Custom path
3. **PHP version** — 8.3, 8.4, or 8.5?
4. **Database** — MySQL or PostgreSQL?
5. **Has queue workers?** — Yes with Horizon / Yes without Horizon (simple queue:work) / No
6. **Has frontend?** — Yes (Vite + Tailwind) / No (API only)
7. **Create GitHub repo?** — Yes (private) / Yes (public) / No

---

## STEP 2 — CREATE THE LARAVEL PROJECT

```bash
cd {{PARENT_DIR}}
composer create-project laravel/laravel {{PROJECT_NAME}} --prefer-dist
cd {{PROJECT_NAME}}
```

If PHP version mismatch is an issue, use:
```bash
composer create-project laravel/laravel {{PROJECT_NAME}} --prefer-dist --ignore-platform-reqs
```

---

## STEP 3 — INITIAL CONFIGURATION

### Install Laravel Pint (if not already included)
```bash
composer require laravel/pint --dev
```

### Add composer scripts (required by CI)
Edit `composer.json` to add these scripts if missing:
```json
"scripts": {
    "lint": "vendor/bin/pint --test",
    "format": "vendor/bin/pint",
    "test": "php artisan test"
}
```

### Install Horizon (if requested)
```bash
php artisan install:horizon
```

### Update `.gitignore`
Ensure these are present (Laravel's default covers most, verify):
```
.env
/vendor
/node_modules
/public/build
/public/storage
/storage/*.key
.phpunit.result.cache
```

---

## STEP 4 — CREATE CLAUDE.md

Create `CLAUDE.md` in the project root. Keep it minimal — the developer will expand it:

```markdown
# {{PROJECT_NAME_TITLE}}

## Stack
- PHP {{PHP_VERSION}}
- Laravel {{LARAVEL_VERSION}} (run `composer show laravel/framework` to get the version)
- Database: {{DB_TYPE}}
{{#if HAS_HORIZON}}- Queue: Laravel Horizon{{/if}}
{{#if HAS_VITE}}- Frontend: Vite + Tailwind CSS{{/if}}

## Local Development
- Copy `.env.example` to `.env` and fill in values
- Run `php artisan key:generate`
- Run `php artisan migrate`
- Start dev server: `php artisan serve` + `npm run dev` (if frontend)

## CI/CD
- Branch strategy: `develop`/`feature/**` → CI → auto-merge → `main` → deploy
- See `.github/workflows/` for pipeline details
- See `.github/setup/secrets-reference.md` for required GitHub secrets
```

---

## STEP 5 — CREATE `.env.production.example`

Copy `.env.example` to `.env.production.example` and sanitize it:
- Replace all real values with safe placeholders
- Add production-specific keys that aren't in the dev example:
  ```
  GHCR_PULL_TOKEN=your-github-pat-with-read:packages-scope
  ```
- Do NOT commit real secrets — this file is a guide only

---

## STEP 6 — INITIALIZE GIT

```bash
git init
git add -A
git commit -m "chore: initial Laravel project scaffold"
git branch develop
git checkout develop
```

The project should start on `develop` so the first real work push triggers CI.

---

## STEP 7 — CREATE GITHUB REPO (if requested)

```bash
gh repo create godiah/{{PROJECT_NAME}} --private --source . --remote origin
git push -u origin main
git push -u origin develop
```

For public repos replace `--private` with `--public`.

---

## STEP 8 — RUN /cicd-setup

After the project and repo are created, immediately run:
```
/cicd-setup
```

The skill will detect the project properties from what was just created (composer.json, .env.example, package.json) and generate all CI/CD files with minimal questions since we already know PHP version, DB type, Horizon, Vite.

Pass the already-gathered information directly to skip re-detection:
- PHP version, DB type, has-Horizon, has-Vite are known
- Still need: PROD_DOMAIN, PROD_SERVER_IP, PROD_PORT from user

---

## STEP 9 — SUMMARY TO USER

After everything is set up, give the user:

```
✅ Project created: {{PARENT_DIR}}/{{PROJECT_NAME}}

📁 Key files:
  CLAUDE.md                     — project context for Claude
  .env.example                  — local dev config template
  .env.production.example       — production config guide (no real secrets)
  .github/workflows/ci.yml      — CI pipeline
  .github/workflows/cd.yml      — CD pipeline
  .github/secrets-reference.md  — what GitHub secrets to configure

🚀 Next steps:
  □ Fill in .env and run: php artisan migrate
  □ Push develop branch to trigger first CI run
  □ Add GitHub secrets (see .github/secrets-reference.md)
  □ Provision server and run: bash .github/setup/server-setup.sh
  □ Set PROD_READY=true in GitHub Variables once server is ready
```
