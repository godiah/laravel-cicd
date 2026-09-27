# Evals

Manual regression checks for the skills in this repo, run against disposable fixture projects instead of a real client project. The point: catch bugs before a template change reaches a client's first production deploy, not after (see `project-cicd-package` memory / commit history for how many bugs were found the hard way).

This is intentionally lightweight — a checklist you or a Claude Code session walks through, not an automated test suite. Docker's own `docker/skills` repo runs its evals the same way for the same reason: it needs a human (or agent) to actually judge "did the generated output do the right thing," which a pure script can't fully cover, and a manual runbook needs no infrastructure to maintain.

## Layout

- `fixtures/<name>/` — a minimal skeleton project (just enough for a skill's detection step to read: `composer.json`, `.env.example`, `package.json`/`vite.config.js` where relevant). Not a working app — never run `composer install` or `artisan` commands against one directly; copy it to a scratch directory first.
- `<skill-name>.md` — the runbook for that skill: a representative prompt, an expected-behaviors checklist, a "must not" list, and verification commands.

## When to run one

After any change to a skill file or a template it uses, before pushing. Copy the relevant fixture to a scratch directory, run the skill against it, walk the checklist.

## Growing this

Start minimal — one fixture per skill covering the modal/common case, one runbook. Add a new fixture only when a real bug surfaces that the existing fixture(s) wouldn't have caught, so this grows against actual failure modes instead of a speculative full stack-variation matrix.
