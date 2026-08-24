#!/usr/bin/env sh

set -eu

infra_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
backup_root=${1:-/srv/lab/backups}
created_at=$(date -u +%Y%m%dT%H%M%SZ)
backup_dir="${backup_root}/${created_at}"

cd "$infra_dir"
test -f .env
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"

restart_application() {
    docker compose up -d cps-app cps-nginx cps-queue > /dev/null
}

trap restart_application EXIT INT TERM
docker compose stop cps-nginx cps-queue cps-app

docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' | gzip > "${backup_dir}/database.sql.gz"
docker run --rm -v lab_cps_photos:/data:ro -v "${backup_dir}:/backup" alpine tar czf /backup/photos.tar.gz -C /data .
docker run --rm -v lab_postfix_dkim:/data:ro -v "${backup_dir}:/backup" alpine tar czf /backup/postfix-dkim.tar.gz -C /data .
install -m 600 .env "${backup_dir}/infra.env"
git rev-parse HEAD > "${backup_dir}/infra-commit.txt"

(
    cd "$backup_dir"
    sha256sum database.sql.gz photos.tar.gz postfix-dkim.tar.gz infra.env infra-commit.txt > manifest.sha256
)

trap - EXIT INT TERM
restart_application

printf '%s\n' "$backup_dir"
