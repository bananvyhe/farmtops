# Locked Stack (lnagovetc)

This project is designed for two modes:
- Local native dev (no Docker)
- Dockerized prod later

## Pinned Versions
- Ruby: 3.3.5
- Rails: 8.0.4 (locked via backend/Gemfile.lock)
- Node.js: 22.22.0
- npm: 10.9.4
- Postgres: 16.12
- Redis: 7.4.8
- Bundler: latest compatible with Ruby 3.3
- Vite: 5.x (via frontend package.json)

See `.tool-versions`, `.ruby-version`, and `.node-version` in the repo root for the locked toolchain.

## Native Install (recommended tools)
You can use any version manager; `mise` is a good choice without requiring admin.

Example (with mise):
- Install mise: `curl https://mise.run | sh`
- Activate it in your shell per mise docs
- Add versions:
  - `mise use -g ruby@3.3.5`
  - `mise use -g node@22.22.0`

Postgres + Redis (mise):
- `mise use -g postgres@16.12`
- `mise use -g redis@7.4.8`

Verify:
- `ruby -v`
- `rails -v`
- `node -v`
- `psql --version`
- `redis-server --version`
