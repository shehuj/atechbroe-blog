# atechbroe-blog

A self-hosted [Ghost](https://ghost.org/) blog running in Docker, with a production-hardened image and an automated CI/CD pipeline that builds, tests, and publishes to Docker Hub via GitHub Actions.

---

## Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start (SQLite)](#quick-start-sqlite)
- [Production Setup (MySQL)](#production-setup-mysql)
- [Environment Variables](#environment-variables)
- [Docker Image](#docker-image)
- [CI/CD Pipeline](#cicd-pipeline)
- [Security Notes](#security-notes)

---

## Overview

| | |
|---|---|
| **Platform** | [Ghost 5](https://ghost.org/) on Alpine Linux |
| **Database** | MySQL 8.0 (production) / SQLite (local testing) |
| **Registry** | Docker Hub |
| **CI/CD** | GitHub Actions |

---

## Project Structure

```
atechbroe-blog/
├── Dockerfile                        # Production-hardened Ghost image
├── docker-compose.yml                # Ghost + MySQL stack
├── .env                              # Local secrets (never commit)
└── .github/
    └── workflows/
        └── docker-build.yml          # Build → Test → Publish pipeline
```

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) 24+
- [Docker Compose](https://docs.docker.com/compose/) v2+
- A [Docker Hub](https://hub.docker.com/) account (for publishing)

---

## Quick Start (SQLite)

Good for local development — no external database needed.

```sh
docker run -d \
  --name atechbroe-blog \
  -p 2368:2368 \
  -e url=http://localhost:2368 \
  -e database__client=sqlite3 \
  -e database__connection__filename=/var/lib/ghost/content/data/ghost.db \
  -v ghost-content:/var/lib/ghost/content \
  ghost:5-alpine
```

Open **http://localhost:2368** in your browser.
Admin panel: **http://localhost:2368/ghost**

---

## Production Setup (MySQL)

**1. Clone the repo**

```sh
git clone https://github.com/<your-username>/atechbroe-blog.git
cd atechbroe-blog
```

**2. Create your `.env` file**

```sh
cp .env.example .env   # or create it manually
```

```env
GHOST_DB_PASSWORD=your_strong_password_here
MYSQL_ROOT_PASSWORD=your_strong_root_password_here
```

**3. Start the stack**

```sh
docker compose up -d
```

Ghost waits for MySQL to pass its health check before starting. Track progress with:

```sh
docker compose logs -f ghost
```

**4. Stop the stack**

```sh
docker compose down
```

Data is persisted in named volumes (`ghost-content`, `ghost-db`) and survives restarts.

---

## Environment Variables

| Variable | Service | Description |
|---|---|---|
| `url` | ghost | Public URL of the blog |
| `database__client` | ghost | `mysql` or `sqlite3` |
| `database__connection__host` | ghost | Database hostname (use `db` with Compose) |
| `database__connection__database` | ghost | Database name |
| `database__connection__user` | ghost | Database user |
| `database__connection__password` | ghost | Database password — use `${GHOST_DB_PASSWORD}` |
| `GHOST_DB_PASSWORD` | db | MySQL password for the `ghost` user |
| `MYSQL_ROOT_PASSWORD` | db | MySQL root password |

> Never hardcode secrets. Use `.env` locally and GitHub/platform secrets in CI.

---

## Docker Image

The `Dockerfile` is built on the official `ghost:5-alpine` image with the following hardening:

| Feature | Detail |
|---|---|
| Non-root user | Runs as `node` — explicitly declared |
| Health check | `wget` polls `localhost:2368` every 30s (90s start period) |
| Named volume | `/var/lib/ghost/content` declared for data persistence |
| Production mode | `NODE_ENV=production` set at image level |
| OCI labels | Standard metadata for registry auditing |

**Build locally:**

```sh
docker build -t atechbroe-blog .
```

**Recommended runtime flags for production:**

```sh
docker run \
  --read-only \
  --security-opt=no-new-privileges \
  --cap-drop=ALL \
  ...
```

---

## CI/CD Pipeline

The pipeline defined in `.github/workflows/docker-build.yml` runs on every push and pull request to `main`.

```
push to main / PR open
        │
        ▼
  build-and-test
  ├── Build image (GHA layer cache)
  ├── Start container with SQLite
  ├── Wait for HEALTHCHECK → healthy
  ├── Assert process runs as 'node'
  └── Assert HTTP 200 on port 2368
        │
        └─── PRs stop here (no publish)
        │
        ▼  (push to main or v*.*.* tag only)
     publish
  ├── Log in to Docker Hub
  ├── Tag strategy:
  │     main branch  →  :main
  │     v1.2.3 tag   →  :1.2.3  and  :1.2
  │     all pushes   →  :sha-<commit>
  └── Build & push (reuses GHA cache)
```

### Required GitHub Secrets

Add these under **Settings → Secrets and variables → Actions**:

| Secret | Description |
|---|---|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token (not your password) — create at hub.docker.com → Account Settings → Personal Access Tokens |

### Tagging strategy

| Event | Tags produced |
|---|---|
| Push to `main` | `:main`, `:sha-<commit>` |
| Push tag `v1.2.3` | `:1.2.3`, `:1.2`, `:sha-<commit>` |
| Pull request | Build & test only, no publish |

---

## Security Notes

- **Secrets** — never commit `.env` or any file containing passwords. `.gitignore` should exclude it.
- **Image pinning** — replace `ghost:5-alpine` with a specific digest in production:
  ```sh
  docker pull ghost:5-alpine
  docker inspect ghost:5-alpine --format '{{index .RepoDigests 0}}'
  # → ghost:5-alpine@sha256:<digest>
  ```
- **CVE scanning** — run `docker scout cves ghost:5-alpine` periodically and rebuild when patches are available.
- **Database passwords** — use a password manager to generate strong, unique values for `GHOST_DB_PASSWORD` and `MYSQL_ROOT_PASSWORD`.
