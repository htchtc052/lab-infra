# Deploy

## Where

Timeweb VPS "Diligent Horologium", 2 vCPU / 3GB RAM / 30GB NVMe.

```
ssh root@104.171.136.141
```

`photo.proclouds.ru`, `photo-api.proclouds.ru` and `mail.proclouds.ru` all resolve to
that same IP — one server runs everything.

Server layout:

```
/srv/lab/
├── backend     ← cps-backend
├── frontend    ← cps-client (kept for source work; not used by production Compose)
└── infra       ← lab-infra
```

## First run

```bash
curl -fsSL https://get.docker.com | sh

mkdir -p /srv/lab && cd /srv/lab
git clone git@github.com:htchtc052/cps-backend.git backend
git clone git@github.com:htchtc052/cps-client.git  frontend
git clone git@github.com:htchtc052/lab-infra.git   infra

cd infra
cp .env.example .env && chmod 600 .env
```

Fill in `.env` — the fields are documented in `.env.example` itself; the ones that
need a real decision rather than a placeholder:

- `API_DOMAIN=photo-api.proclouds.ru`, `APP_DOMAIN=photo.proclouds.ru`,
  `MAIL_DOMAIN=proclouds.ru`
- `APP_KEY` — generate with `echo "base64:$(openssl rand -base64 32)"`
- `DB_PASSWORD`, `REDIS_PASSWORD` — pick anything, write it down; nothing else
  references them except this file
- `ACME_EMAIL` — real inbox, Let's Encrypt expiry notices go here

`API_DOMAIN`/`APP_DOMAIN` must already resolve to this server before the first
`up -d` — Let's Encrypt's HTTP challenge needs to reach the container.

```bash
docker compose build cps-app cps-nginx
docker compose up -d
docker compose exec cps-app php artisan migrate --force
```

## Update (the normal case)

The frontend image is built and published by `cps-client` GitHub Actions on every
push to `main`. To update it on the VPS, manually run the `Deploy frontend`
workflow in `lab-infra` after the image build succeeds. The workflow pulls
`ghcr.io/htchtc052/cps-client:latest` and recreates only `cps-client`.

Backend updates remain local builds until their own publishing workflow exists:

```bash
cd /srv/lab
git -C backend pull --ff-only
git -C infra pull --ff-only
cd infra && docker compose build cps-app cps-nginx
docker compose up -d cps-app cps-nginx cps-queue
docker compose exec cps-app php artisan migrate --force
```

## GitHub Actions deploy setup

The `Deploy frontend` workflow runs only by manual dispatch. Add these repository
secrets in `htchtc052/lab-infra` before its first run:

- `VPS_HOST` — `104.171.136.141`
- `VPS_SSH_KEY` — the existing private key that can log in as `root`

The current GHCR package can be pulled by the VPS without a registry login, so no
package token belongs on the server or in GitHub Actions.

A key added to `.env.example` doesn't propagate — add it to the server's `.env` by
hand, or the container starts without it.

## `.env` has exactly one copy

It lives only at `/srv/lab/infra/.env` (`chmod 600`, root-only) — not checked into
git, not mirrored anywhere else. If it's gone, there's nothing to restore: rebuild
it from `.env.example` with a fresh `APP_KEY` and fresh DB/Redis passwords. That
invalidates existing sessions and requires the new DB password to match what
Postgres actually has (or a fresh `migrate` on an empty database).

## Data backup / restore

```bash
cd /srv/lab/infra
docker compose exec -T postgres pg_dump -U curated_photo curated_photo | gzip > ~/db.sql.gz
docker run --rm -v lab_cps_photos:/data -v ~:/backup alpine tar czf /backup/photos.tar.gz -C /data .
```

Restore on a clean server — instead of `migrate --force`:

```bash
docker compose up -d postgres
gunzip -c ~/db.sql.gz | docker compose exec -T postgres psql -U curated_photo curated_photo
docker run --rm -v lab_cps_photos:/data -v ~:/backup alpine tar xzf /backup/photos.tar.gz -C /data
docker compose up -d
```
