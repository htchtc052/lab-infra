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

## Runtime secrets

The live file is `/srv/lab/infra/.env` (`chmod 600`, root-only) — it is not
checked into git and not copied into GitHub Secrets. A portable backup includes a
copy named `infra.env`; anyone who obtains that backup obtains all runtime
secrets. Keep the downloaded bundle in encrypted storage. If both `.env` and
every backup are gone, rebuild it from `.env.example` with fresh secrets and use
a clean database.

## Portable backup

This is the provider-independent recovery path. It briefly stops the API and
queue so the database and photo volume describe the same state, then restarts
them. It stores Postgres, photos, DKIM, `.env`, checksums and the infra commit:

```bash
ssh root@<VPS_HOST> 'cd /srv/lab/infra && ./scripts/backup.sh'
```

The command prints `/srv/lab/backups/<UTC timestamp>`. The backup is not safe
while it remains on the VPS being deleted. Download that exact directory:

```bash
scp -r root@<VPS_HOST>:/srv/lab/backups/<UTC timestamp> ./
```

Keep it in private encrypted storage. Redis is intentionally excluded; sessions,
cache and pending queue state are disposable. ACME certificates are also omitted
and are issued again from DNS.

## Restore a portable backup

Prepare a fresh server and clone `lab-infra` as above, but do not create `.env`
and do not start Compose. Upload the backup directory, then run:

```bash
scp -r ./<UTC timestamp> root@<VPS_HOST>:/srv/lab/backups/
ssh -t root@<VPS_HOST> \
  'cd /srv/lab/infra && ./scripts/restore.sh /srv/lab/backups/<UTC timestamp>'
```

The restore script verifies checksums and refuses to touch a server where any
target data volume already exists. It installs `.env`, restores Postgres, photos
and DKIM, applies any newer forward migrations, pulls current images and starts
the complete stack. Then update DNS and `VPS_HOST` if the address changed and run
the two public `curl` checks from **Fresh server**.

## Deliberately reset production data

This is not deployment. Run it only after an explicit decision to discard the
database, uploaded photos, Redis state and sessions. It deliberately preserves
Traefik certificates and DKIM:

```bash
cd /srv/lab/infra
./scripts/backup.sh                         # optional last recovery point
docker compose pull
docker compose down
docker volume rm lab_pg_data lab_redis_data lab_cps_photos
docker compose up -d --wait postgres redis
docker compose run --rm cps-app php artisan migrate --force
docker compose run --rm cps-app php artisan app:ensure-admin owner@example.com --name="Owner"
docker compose up -d
```

Never replace the named `docker volume rm` command with `docker compose down -v`:
that would also delete ACME certificates and the mail DKIM key.

The current operational trade-offs are recorded in
[`DECISIONS.md`](DECISIONS.md).
