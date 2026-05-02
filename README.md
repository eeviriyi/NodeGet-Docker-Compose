# NodeGet Docker Compose

Single-domain Docker Compose deployment for NodeGet.

Routes:

- `/` serves NodeGet-StatusShow
- `/board/` serves NodeGet-board
- `/ws` proxies NodeGet Server WebSocket JSON-RPC

The stack uses Caddy for automatic HTTPS, Postgres for storage, and the official NodeGet server image.

## Requirements

- Docker with Compose support
- A domain name pointed to this server
- Inbound ports `80` and `443` open

## Quick Start

```bash
git clone https://github.com/eeviriyi/NodeGet-Docker-Compose.git
cd NodeGet-Docker-Compose
cp .env.example .env
nano .env
./scripts/up.sh
```

Before starting, set at least:

```env
DOMAIN=nodeget.example.com
ACME_EMAIL=admin@example.com
POSTGRES_PASSWORD=change-this-password
STATUS_BACKEND_URL=wss://nodeget.example.com/ws
```

After the stack starts:

1. Open `https://YOUR_DOMAIN/board/`.
2. Get the NodeGet SuperToken from `docker compose logs nodeget-server` or the generated server config.
3. Add the backend URL `wss://YOUR_DOMAIN/ws` in the board.
4. Create a public/read-only token for StatusShow.
5. Put that token in `.env` as `STATUS_TOKEN`.
6. Run:

```bash
./scripts/render-status-config.sh
docker compose restart nodeget-statusshow
```

Then open `https://YOUR_DOMAIN/`.

## DNS

Create an `A` record at your DNS provider:

```text
nodeget.example.com -> your server IPv4
```

Create an `AAAA` record too if you use IPv6.

## HTTPS

Caddy automatically requests and renews Let's Encrypt certificates. The domain must already resolve to this server, and ports `80` and `443` must be reachable from the public internet.

## Images

- NodeGet Server: `genshinmc/nodeget:latest`
- Postgres: `postgres:17-alpine`
- Caddy: `caddy:2-alpine`
- Board and StatusShow are built from the configured Git repositories.

For production, pin versions in `.env` instead of using `latest`.

## Common Commands

```bash
docker compose ps
docker compose logs -f nodeget-server
docker compose logs -f caddy
docker compose pull
docker compose up -d --build
```

