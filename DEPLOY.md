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
git clone https://github.com/htchtc052/lab-infra.git infra

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
The public key matching the GitHub `VPS_SSH_KEY` secret must be installed for
`root`, either while creating the VPS or in `/root/.ssh/authorized_keys`.

```bash
docker compose pull
docker compose up -d postgres redis
docker compose run --rm cps-app php artisan migrate --force
docker compose run --rm cps-app php artisan app:ensure-admin owner@example.com --name="Owner"
docker compose up -d
api_domain="$(sed -n 's/^API_DOMAIN=//p' .env | head -n 1)"
app_domain="$(sed -n 's/^APP_DOMAIN=//p' .env | head -n 1)"
curl --fail "https://${api_domain}/up"
curl --fail "https://${app_domain}/" > /dev/null
```

`app:ensure-admin` asks for a new password without echoing it. If the email
already exists, the command only grants administrator access and leaves the
existing password unchanged. It is safe to repeat.

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
are not replaced. Both deploy workflows finish with a retried public HTTP check
and fail if the updated endpoint does not answer successfully.

The same manual deploy can be started from an authenticated GitHub CLI:

```bash
gh workflow run deploy-frontend.yml --repo htchtc052/lab-infra --ref main
gh workflow run deploy-backend.yml  --repo htchtc052/lab-infra --ref main
gh run list --repo htchtc052/lab-infra --workflow deploy-frontend.yml --limit 1
gh run list --repo htchtc052/lab-infra --workflow deploy-backend.yml --limit 1
gh run watch <run-id> --repo htchtc052/lab-infra
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

- For a planned Timeweb pause, create or download a full server image and keep
  its public IP if convenient. Restore a server from that image and attach the
  same IP; DNS and `VPS_HOST` do not need changing. See
  [`TIMEWEB.md`](TIMEWEB.md).
- A native Timeweb backup can also be downloaded and later uploaded as an image;
  this uses the hosting recovery mechanism rather than project scripts.
- For a completely clean server, use **Fresh server** above. It creates an empty
  database and a new administrator. Then update DNS records and `VPS_HOST` if the
  server address changed.

After restoring an image, start a manual frontend and/or backend deploy to fetch
the current application images. **Fresh server** already pulls them. If the old
server was deleted without an image or backup, its database, photos and `.env`
cannot be reconstructed from GHCR.

## Runtime secrets

The live file is `/srv/lab/infra/.env` (`chmod 600`, root-only). It is not checked
into git and not copied into GitHub Secrets. A full Timeweb image or backup
contains this file together with the Docker volumes. A clean installation creates
a new `.env`, `APP_KEY`, database password and Redis password.

## Deliberately reset production data

This is not deployment. Run it only after an explicit decision to discard the
database, uploaded photos, Redis state and sessions. It deliberately preserves
Traefik certificates and DKIM:

```bash
cd /srv/lab/infra
docker compose pull cps-app
docker compose down
docker volume rm lab_pg_data lab_redis_data lab_cps_photos
docker compose up -d --wait postgres redis
docker compose run --rm cps-app php artisan migrate --force
docker compose run --rm cps-app php artisan app:ensure-admin owner@example.com --name="Owner"
docker compose up -d
```

`docker compose pull cps-app` only refreshes the locally cached application
image; it does not replace the running container. The following one-off
`migrate` and `app:ensure-admin` commands must come from the current image.

The named volumes discard only the database, Redis and uploaded photos. Traefik
certificates and the mail DKIM key remain in their separate volumes.
