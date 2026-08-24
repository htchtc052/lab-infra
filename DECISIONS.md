# Operational decisions

These are current project choices, not accidental workflow limitations.

## Independent repositories and releases

Frontend, backend and infrastructure remain separate repositories. A frontend
change neither rebuilds nor deploys the backend, and vice versa.

## Automatic publish, explicit deploy

Every push to `main` publishes the affected component to GHCR. Production changes
only through a manually dispatched `lab-infra` deploy workflow.

## `latest` only

The project intentionally publishes only mutable `latest` tags. This keeps the
solo test-project workflow small, but means a deployment cannot select or roll
back to an exact image digest. To return to older code, revert it on `main`, wait
for a new `latest` build, then deploy again.

## Forward migrations

Normal deployment preserves production data and runs `migrate --force` before
recreating backend containers. Migrations must be additive or otherwise
compatible with the currently running application during that short interval.
Destructive schema cleanup belongs in a later migration after the new code is
already deployed.

## Replaceable VPS, two recovery levels

A downloaded Timeweb Qcow2 image is the shortest full-machine recovery path. A
portable application backup contains Postgres, photos, DKIM and `.env`; it can
bootstrap a clean Docker host without preserving the old VPS. Redis and ACME
certificates are disposable and are recreated.

## Secrets remain on the server

Application, database, Redis and mail secrets are not copied into GitHub. Only
the target address and SSH deployment key are GitHub repository secrets. A
portable backup therefore contains a sensitive copy of `.env` and must be kept
private.

## Root deployment access

The workflow connects as `root`. A dedicated deploy user would reduce privilege,
but is deliberately deferred for this single-owner test environment.

## Reset is manual and explicit

An empty production database is currently acceptable, but reset is never part of
build or deploy. It requires an explicit command sequence and administrator
bootstrap from `DEPLOY.md`.
