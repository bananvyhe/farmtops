# New Project Cheatsheet

This file is a running checklist of practical fixes that should be applied early when creating a new project from this template.

## 0) Environment strategy (agreed)

- Local development:
  - Run native (no Docker for now).
  - Keep the full dev environment up during active work:
    - PostgreSQL
    - Redis
    - Rails API
    - Sidekiq worker
    - Vue frontend
  - Use project scripts:
    - `./scripts/dev_services_up.sh`
    - `./scripts/dev_up.sh`
    - `./scripts/dev_services_down.sh`
- Production / VPS:
  - Deploy in Docker.
  - Keep CI image build always enabled.
  - Push image to registry manually when needed (release/deploy moment).
  - Periodic jobs are scheduled through `sidekiq-cron`.

## 0.1) Architecture rules

- Frontend is always `Vue 3 Composition API`.
- Rails is used as API/backend and owns all sensitive calculations and security logic.
- Do not fall back to server-rendered HTML as the main UI path unless explicitly requested.

## 1) Native startup reliability

- Problem pattern:
  - Frontend opens before backend is ready.
  - Browser shows `ERR_CONNECTION_REFUSED` for API calls.
  - Stale PID files make scripts think services are running when they are not.

- Required baseline:
  - In startup scripts, remove stale PID files if process is not alive (`kill -0` check).
  - Wait for backend health endpoint before reporting success (for Rails: `GET /up`).
  - Fail fast with clear log pointer when backend does not start.

- Implemented in this project:
  - `scripts/native_up.sh`
  - `scripts/native_up_full.sh`

## 2) GitHub Actions: GHCR push

- Problem pattern:
  - `Build and Push Docker Image / build (push)` fails.
  - Wrong/static image name in workflow points to another package/repo.

- Required baseline:
  - Use dynamic image name from repo:
    - `ghcr.io/${{ github.repository }}`
  - Ensure repository Actions permissions allow write for packages.

- Implemented in this project:
  - `.github/workflows/build-image.yml`

## 3) Locked stack and versions

- Pin and keep in sync:
  - Ruby `3.3.5` in:
    - `.ruby-version`
    - `.tool-versions`
  - Node `22.22.0` in:
    - `.node-version`
    - `.tool-versions`
  - Postgres `16.12` in:
    - `.tool-versions`
  - Redis `7.4.8` in:
    - `.tool-versions`
  - Rails and Ruby gems in:
    - `backend/Gemfile.lock`
  - Frontend packages in:
    - `frontend/package-lock.json`
  - Docker build contract in:
    - `backend/Dockerfile` (`ARG RUBY_VERSION`, build args)
    - `.github/workflows/build-image.yml`

- Rule:
  - If tool/package version changes, update all related lock/version files in one commit.
  - Do not leave partial upgrades.

- Source of truth:
  - `docs/STACK.md`

## 4) Background jobs

- Current project:
  - Use Redis + Sidekiq.
  - Schedule recurring jobs through `sidekiq-cron`.
  - Billing can go negative; do not block charges on negative balances.
- Required baseline:
  - Add process supervision for worker startup/shutdown.
  - In Docker deploy include a separate Sidekiq service/container.
  - In native dev provide dedicated start/stop scripts.
  - Keep environment-specific scheduling:
    - Dev: shorter interval (3 min) for fast feedback.
    - Prod: hourly interval.
    - Use `BILLING_INTERVAL_MINUTES` to override safely.

- Common failure modes:
  - Scheduler runs but no списания appear:
    - confirm `sidekiq` is alive
    - confirm users actually have `effective_hourly_rate_cents > 0`
  - Imported users may have zero tariff/manual hourly rate after migration.
  - Then scheduler works, but no `hourly_charge` rows are created.

## 4.1) Production secrets and deploy

- If `Rails credentials` are copied into the repo and then baked into Docker image:
  - updating `config/credentials.yml.enc` on the server filesystem is not enough
  - you must rebuild the app images
- New project rule:
  - put app secrets in `Rails credentials` from day one
  - keep only infra secrets in `.env.production`
  - never commit `config/master.key` or real env files
- Keep a local deploy script in the template from day one:
  - sync project files
  - sync `config/credentials.yml.enc`
  - never sync `config/master.key`
  - rebuild and restart target services
- Keep `RAILS_MASTER_KEY` in server env, not as a file in the repo checkout on VPS.
- Keep infra secrets like `POSTGRES_PASSWORD` in server env because Docker/Postgres need them before Rails boots.
- Keep app secrets in `Rails credentials`.

## 5) Frontend data loading

- Problem pattern:
  - Data appears missing on first page open.
  - Root cause is usually backend unavailable at startup, not Vue `nextTick`.

-- Required baseline:
  - First fix environment startup reliability.
  - Do not use `nextTick` as a network fix.
  - Add UI retry only if there are proven transient upstream failures.

## 6) SEO baseline

- Required baseline:
  - Correct `<title>` and `<meta name="description">`.
  - OG/Twitter tags.
  - Canonical link.
  - `robots.txt` with sitemap reference.
  - `sitemap.xml` with main public routes.

- Implemented in this project:
  - `frontend/index.html`
  - `frontend/src/packs/router/index.js` (route-level meta updates)
  - `backend/public/robots.txt`
  - `backend/public/sitemap.xml`

## 7) Clone pitfalls (Farmspot experience)

- Ports already in use:
  - Rails on `127.0.0.1:3000` and Vite on `127.0.0.1:5173` silently fail when those ports are occupied.
  - If `./scripts/dev_up.sh` exits instantly with no logs, run services in foreground to see the bind error.
  - Fix: stop the other project or choose alternative ports and update `frontend/vite.config.js` proxy.
- Sidekiq depends on Redis + DB:
  - If Redis is not running, Sidekiq crashes at boot.
  - If the database is missing, `sidekiq-cron` will immediately enqueue jobs and blow up with `NoDatabaseError`.
  - Fix: run `./scripts/dev_services_up.sh` first, then `bundle exec rails db:prepare`, then start Sidekiq.
- Rename leftovers:
  - Search for uppercase branding strings (e.g., `PIXELUP`) in templates.
  - Update env var names if they were project-specific (example: `PIXELUP_DATABASE_PASSWORD`).
