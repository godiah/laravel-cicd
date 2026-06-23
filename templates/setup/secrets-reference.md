# GitHub Actions — Required Secrets & Variables

Set these under **Settings → Secrets and variables → Actions** in the repository.

---

## Repository Secrets

### CI/CD Pipeline (always required)

| Secret | Description |
|--------|-------------|
| `GH_PAT` | GitHub Personal Access Token with `repo` scope — used by the CI `auto-merge` job to push to `main` |
| `GHCR_PULL_TOKEN` | GitHub PAT with `read:packages` scope — used by the production server to pull images from GHCR. Generate at GitHub → Settings → Developer settings → Tokens |
| `PROD_SSH_HOST` | Production server IP (`{{PROD_SERVER_IP}}`) |
| `PROD_SSH_USER` | SSH user on the server (e.g. `deploy` or `root`) |
| `PROD_SSH_KEY` | ED25519 private key — generate with `ssh-keygen -t ed25519`; add the public key to the server's `~/.ssh/authorized_keys` |

> **`GITHUB_TOKEN`** is auto-provided by Actions for GHCR image pushes — no manual secret needed.

### Second Server (only if cd-production.yml is generated)

| Secret | Description |
|--------|-------------|
| `PROD2_SSH_HOST` | Second production server IP |
| `PROD2_SSH_USER` | SSH user on the second server |
| `PROD2_SSH_KEY` | ED25519 private key for the second server |

### Application Secrets (project-specific — add based on .env.example)

Add secrets for all sensitive values in `.env.example`. Common ones:

| Secret | Description |
|--------|-------------|
| `APP_KEY` | Laravel app key — generate with `php artisan key:generate --show` |
| `DB_PASSWORD` | Production database password |
| `REDIS_PASSWORD` | Redis auth password (if configured) |
| `MAIL_USERNAME` | SMTP username |
| `MAIL_PASSWORD` | SMTP password |

> Review `.env.example` and add a secret for every variable that contains API keys,
> passwords, tokens, or other credentials. Non-sensitive variables go in **Variables** (below).

---

## Repository Variables (non-sensitive)

Set these under **Settings → Secrets and variables → Actions → Variables**.

| Variable | Example | Description |
|----------|---------|-------------|
| `PROD_READY` | `true` | Set to `true` after the server is provisioned to enable the CD deploy job. Until then the build runs but deploy is skipped. |
| `APP_URL` | `https://{{PROD_DOMAIN}}` | Production URL |
| `APP_ENV` | `production` | Laravel environment |

---

## How to Generate the SSH Key Pair

```bash
# On your local machine — generates a key pair specific to this project
ssh-keygen -t ed25519 -C "{{APP_NAME_SLUG}}-deploy" -f ~/.ssh/{{APP_NAME_SLUG}}_deploy

# 1. Add the PUBLIC key to the server:
ssh-copy-id -i ~/.ssh/{{APP_NAME_SLUG}}_deploy.pub deploy@{{PROD_SERVER_IP}}
# Or manually append to: /home/deploy/.ssh/authorized_keys

# 2. Add the PRIVATE key to GitHub secrets as PROD_SSH_KEY:
cat ~/.ssh/{{APP_NAME_SLUG}}_deploy
```

## How to Generate GHCR_PULL_TOKEN

1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. New token → select `read:packages` scope
3. Add as `GHCR_PULL_TOKEN` secret in the repo **AND** add to `{{DEPLOY_PATH}}/.env` on the server as `GHCR_PULL_TOKEN=<token>`

---

## Notes

- Rotate all secrets before go-live
- Never commit actual `.env` values to git — the `.env` on the server is the source of truth
- The `GITHUB_TOKEN` automatically expires per workflow run — no rotation needed
- For M-Pesa, Jenga, or other payment integrations, add API keys as secrets and reference them in `.env.example` with placeholder values
