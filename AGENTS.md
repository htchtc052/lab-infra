# CuratedPhoto operations agent

## Workspace

- `cps-client`, `cps-backend` and `lab-infra` are independent repositories and
  are committed and pushed independently.
- `DEPLOY.md` is the operational source of truth. `TIMEWEB.md` contains
  provider-specific image, pause and recovery steps.
- Production runs published GHCR images. Source checkouts of the frontend and
  backend do not belong on the VPS.

## Delivery

- A push to `main` in `cps-client` or `cps-backend` automatically publishes its
  `latest` image. It does not deploy it.
- Deploy only when the user explicitly asks to change production. Run the
  matching manual workflow in `lab-infra` and wait for its HTTP verification.
- Frontend and backend deploy independently. Do not deploy the other component
  merely because it also has unpublished changes.
- Backend deployment runs forward migrations before replacing the application
  containers. Never use `migrate:fresh` as part of deployment.

## State and secrets

- Runtime secrets live only in `/srv/lab/infra/.env`. GitHub Actions holds only
  `VPS_HOST` and `VPS_SSH_KEY` for deployment.
- The VPS is replaceable. `VPS_HOST`, DNS and the SSH authorized key are the
  pointers that must be updated when the target server changes.
- Never run `docker compose down -v`. It would remove unrelated persistent
  state, including certificates and DKIM keys.
- Database reset is allowed only after an explicit user request. Use the named
  volume procedure in `DEPLOY.md`.
