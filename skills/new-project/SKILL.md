---
name: new-project
description: Use this skill when the user asks to create a new Laravel project, scaffold a new project, start a new Laravel app, or just says "new project". Sets up a fully-configured greenfield Laravel project end-to-end — composer scaffold, git branches, CLAUDE.md, .env.production.example, optional GitHub repo creation — then immediately invokes the cicd-setup skill so CI/CD is wired from day one.
---

# New Laravel Project

## Overview

Scaffolds a brand-new Laravel project with every convention this workflow relies on wired in from the first commit, then hands off to `cicd-setup` so the project never goes through a period of existing without CI/CD.

## When to use this skill

- "create a new Laravel project" / "scaffold a new project" / "start a new Laravel app" / "new project"

## Do not use this skill when

- The project already exists — this is for greenfield scaffolds only. To add CI/CD to an existing project, use `cicd-setup` directly instead.
- The target directory already has files in it — `composer create-project` will silently merge into whatever's there rather than failing loudly. Confirm the directory is genuinely empty/new, or pick a different path, before proceeding.
- The user only wants the CI/CD pipeline, not a new Laravel install — use `cicd-setup` alone.

## What this skill produces

- A new Laravel project with `composer create-project`
- Git initialized with `main` + `develop` branches
- `CLAUDE.md` with project context
- `.env.production.example` ready for server setup
- GitHub repo created (optional)
- CI/CD fully configured via `cicd-setup`

---

## Step 1 — Gather project details

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

## Step 2 — Create the Laravel project

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

## Step 3 — Initial configuration

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

## Step 4 — Create CLAUDE.md

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

## Step 5 — Create `.env.production.example`

Copy `.env.example` to `.env.production.example` and sanitize it:
- Replace all real values with safe placeholders
- Add production-specific keys that aren't in the dev example:
  ```
  GHCR_PULL_TOKEN=your-github-pat-with-read:packages-scope
  ```
- Do NOT commit real secrets — this file is a guide only

---

## Step 6 — Initialize git

```bash
git init
git add -A
git commit -m "chore: initial Laravel project scaffold"
git branch develop
git checkout develop
```

The project should start on `develop` so the first real work push triggers CI.

---

## Step 7 — Create GitHub repo (if requested)

```bash
gh repo create godiah/{{PROJECT_NAME}} --private --source . --remote origin
git push -u origin main
git push -u origin develop
```

For public repos replace `--private` with `--public`.

---

## Step 8 — Invoke cicd-setup

After the project and repo are created, immediately invoke the `cicd-setup` skill.

It will detect the project properties from what was just created (composer.json, .env.example, package.json) and generate all CI/CD files with minimal questions since PHP version, DB type, Horizon, and Vite are already known.

Pass the already-gathered information directly to skip re-detection:
- PHP version, DB type, has-Horizon, has-Vite are known
- Still need: PROD_DOMAIN, PROD_SERVER_IP, PROD_PORT from user

---

## Step 9 — Summary to user

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

---

## Destructive operations

State exactly what will happen and get explicit confirmation before any of the following:

- **Creating the GitHub repo as public** — once cloned or indexed elsewhere this is effectively irreversible. Confirm private vs. public explicitly; default to private if the user doesn't say.
- **Running `composer create-project` into a non-empty directory** — it merges silently into existing files instead of failing. Confirm the target directory is genuinely new first.
- **The initial `git push -u origin main`/`develop`** assumes a brand-new, empty remote. If `gh repo create` reports the repo already exists, stop and ask rather than pushing into it.

---

## Related skills

- Generates the CI/CD pipeline this skill invokes as its final step: `cicd-setup`
- Roll back a bad production deployment: `rollback`
