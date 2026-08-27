# Farmspot

Rails API + Sidekiq backend and Vue/Vuetify frontend for the Farmspot game platform.

Start the supported development environment with Docker Compose:

```bash
cp .env.development.example .env.development
docker compose --env-file .env.development -f docker-compose.dev.yml up --build
```

Open http://localhost:8082. The Rails health endpoint is http://localhost:3002/up.

Project context: [docs/index.md](docs/index.md). Development commands and troubleshooting: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Stack and deployment boundaries: [docs/STACK.md](docs/STACK.md).

## Windows + WSL development rules

- Run Docker Desktop with the Linux engine and use the local Docker context: `docker context use default`.
- The WSL shell may start the containers, but the browser must open the published host URL: `http://localhost:8082`.
- `web`, `postgres`, and `redis` are container-only names. Do not use them in the Windows browser; do not use `localhost` for service-to-service URLs inside Compose.
- The Vite server must listen on `0.0.0.0` inside its container. The Compose port publishes it to Windows as `localhost:8082`.
- After changing Dockerfiles, Compose, or frontend dependencies, use `bash scripts/dev_up.sh` (it rebuilds images). After source-only changes, Vite hot reload is sufficient.
- Before reporting a blank page, verify both endpoints:

  ```powershell
  Invoke-WebRequest http://localhost:8082/
  Invoke-WebRequest http://localhost:3002/up
  ```

- If the frontend is healthy but the page is blank, inspect the browser console and run `docker compose -f docker-compose.dev.yml logs frontend`.
