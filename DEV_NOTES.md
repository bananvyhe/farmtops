# Dev Notes

- Canonical context entry: [docs/index.md](/Users/rufus/workspace/projects/farmspot/docs/index.md).
- Keep this file operational, not encyclopedic. Do not repeat material that already lives in the docs tree.
- Treat user edits in the workspace as intentional unless they directly block the current task.
- Keep local dev runnable end to end: PostgreSQL, Redis, Rails, Sidekiq, Vite frontend.
- Production deploy is Docker-only; use `./scripts/deploy_prod.sh` for VPS deploys.
- News translation depends on host-to-container access to `NEWS_TRANSLATOR_BASE_URL`; if Sidekiq times out, check UFW and allow Docker bridge traffic to `19191/tcp`.
- Translation is a lock-guarded one-article chain and should advance only on job completion or the one-shot boot recovery.
- The recovery entrypoint is `bundle exec rake news:translation:recover`.
- Rebuild app containers after any credentials change; `restart` is not enough when `config/credentials.yml.enc` changes.
- Keep app secrets in `Rails credentials`; keep only infra boot secrets in `.env.production`.
- Billing can go negative; do not block hourly charges on negative balances.
- Verify imported users after migration: tariff assignment, hourly rates, and ledger rows.
- Common clone pitfalls: port collisions on `3000/5173`, Sidekiq starting before Redis/DB, and stale branding/env vars from template projects.
