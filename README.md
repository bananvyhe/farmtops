# Farmspot

Rails API + Sidekiq backend and Vue/Vuetify frontend for the Farmspot game platform.

Start the supported development environment with Docker Compose:

```bash
cp .env.development.example .env.development
docker compose --env-file .env.development -f docker-compose.dev.yml up --build
```

Open http://localhost:8082. The Rails health endpoint is http://localhost:3002/up.

Project context: [docs/index.md](docs/index.md). Development commands and troubleshooting: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Stack and deployment boundaries: [docs/STACK.md](docs/STACK.md).
