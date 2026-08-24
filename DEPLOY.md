# Deploy

## Target server

Production is one replaceable Linux VPS. Its active public address is held in the
`VPS_HOST` secret of `htchtc052/lab-infra`; it is deliberately not written here.
The deploy workflows connect as `root` to that address.

`photo.proclouds.ru`, `photo-api.proclouds.ru` and `mail.proclouds.ru` must all
resolve to the active server's address. Timeweb-specific pause and recovery steps
are in [`TIMEWEB.md`](TIMEWEB.md).

Server layout:

```
/srv/lab/
└── infra       ← lab-infra, Compose and the production `.env`
```

## Fresh server

```bash
curl -fsSL https://get.docker.com | sh

mkdir -p /srv/lab && cd /srv/lab
git clone git@github.com:htchtc052/lab-infra.git infra

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
docker compose pull
docker compose up -d postgres redis
docker compose run --rm cps-app php artisan migrate --force
docker compose up -d
```

The VPS never builds the application. It downloads the ready `latest` images
from GHCR; the database, uploaded photos and `.env` are created or restored on
this server separately.

## Update (the normal case)

1. Commit and push to `main` locally. The corresponding `cps-client` or
   `cps-backend` workflow automatically builds and publishes its `latest` image
   to GHCR. Wait for that build to succeed.
2. Deploy is a separate explicit action. In GitHub, open
   `htchtc052/lab-infra` → **Actions** → **Deploy frontend** or **Deploy backend**
   → **Run workflow** → `main` → **Run workflow**.

The frontend deploy pulls `ghcr.io/htchtc052/cps-client:latest` and recreates
only `cps-client`.

The backend images are built and published by `cps-backend` GitHub Actions on
every push to `main`. To update them on the VPS, manually run the `Deploy backend`
workflow in `lab-infra`. It pulls `cps-app:latest` and `cps-nginx:latest`, applies
forward migrations with a temporary container, then recreates `cps-app`,
`cps-nginx` and `cps-queue`. If a migration fails, the running backend containers
are not replaced.

The same manual deploy can be started from an authenticated GitHub CLI:

```bash
gh workflow run deploy-frontend.yml --repo htchtc052/lab-infra --ref main
gh workflow run deploy-backend.yml  --repo htchtc052/lab-infra --ref main
gh run watch --repo htchtc052/lab-infra
```

Run only the workflow for the component whose image you intend to put in
production. A successful image build does not change the VPS by itself.

## GitHub Actions deploy setup

The `Deploy frontend` and `Deploy backend` workflows run only by manual dispatch.
They use these repository secrets in `htchtc052/lab-infra`:

- `VPS_HOST` — active public IP or DNS name of the target VPS; update it after a
  move to a new server
- `VPS_SSH_KEY` — the existing private key that can log in as `root`

The current GHCR package can be pulled by the VPS without a registry login, so no
package token belongs on the server or in GitHub Actions.

A key added to `.env.example` doesn't propagate — add it to the server's `.env` by
hand, or the container starts without it.

## Move, delete or recreate a VPS

Yes: application images are replaceable and are always downloadable from GHCR.
They are not a full server backup: they do not contain Postgres data, uploaded
photos, Docker volumes or `.env`.

- For a planned Timeweb pause, create a server snapshot and keep its public IP.
  Restore a server from that snapshot and attach the same IP; DNS and `VPS_HOST`
  do not need changing. See [`TIMEWEB.md`](TIMEWEB.md).
- For a completely new server, use **Fresh server** above, restore the database
  and photos if they are needed, then update DNS records and the `VPS_HOST`
  GitHub secret. The SSH public key matching `VPS_SSH_KEY` must also be present
  for the manual deploy workflows to work.

After either path, start a manual frontend and/or backend deploy to fetch the
current images. If the old server was deleted without a snapshot or backups, its
database, photos and `.env` cannot be reconstructed from GHCR.

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
