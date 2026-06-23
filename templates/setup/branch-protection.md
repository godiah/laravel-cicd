# Branch Protection Rules for `main`

Configure under **Settings → Branches → Add rule** → Branch name pattern: `main`

## Required Settings

| Setting | Value | Reason |
|---------|-------|--------|
| Require a pull request before merging | ✅ | No direct pushes to main |
| Required approvals | 1 | At minimum one peer review |
| Dismiss stale PR approvals when new commits are pushed | ✅ | Re-review after changes |
| Require status checks to pass before merging | ✅ | CI must be green |
| Required status checks | `test`, `lint`, `build-check` | Match CI job names exactly |
| Require branches to be up to date before merging | ✅ | No stale-branch merges |
| Do not allow bypassing the above settings | ✅ | Applies to admins too |

> **Note:** The `auto-merge` CI job pushes directly to `main`. For this to work, the
> `GH_PAT` token must belong to a user who is allowed to bypass branch protection,
> OR you can use a GitHub App token for the merge step. If direct pushes are blocked
> even for `GH_PAT`, add an exclusion for the Actions bot under "Restrict who can push."

## Recommended Additions

- **Require signed commits** — enable once team GPG/SSH signing is set up
- **Allow force pushes** — keep **disabled** on main; use `--force-with-lease` on feature branches only
- **Allow deletions** — keep **disabled** on main

## Alternative: GitHub Rulesets (newer)

GitHub Rulesets (**Settings → Rules → Rulesets**) offer the same protections with better
inheritance across forks and organisations. Prefer Rulesets for new repositories on GitHub
Enterprise or organisations.

## CI Job Names Reference

Update the "Required status checks" above to match the actual job names in `.github/workflows/ci.yml`:

| Job name in CI | What it does |
|----------------|--------------|
| `lint` | Pint code style check |
| `audit` | Composer security audit |
| `analyse` | PHPStan static analysis (if enabled) |
| `test` | Full test suite with real DB + Redis |
| `build-check` | Docker build + artisan cache smoke test |
| `auto-merge` | Merges develop → main (only on push, not PRs) |
