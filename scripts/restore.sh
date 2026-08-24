#!/usr/bin/env sh

set -eu

if [ "$#" -ne 1 ]; then
    printf 'Usage: %s /path/to/backup-directory\n' "$0" >&2
    exit 2
fi

infra_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
backup_dir=$(CDPATH= cd -- "$1" && pwd)

cd "$backup_dir"
sha256sum -c manifest.sha256

for volume in lab_pg_data lab_redis_data lab_cps_photos lab_postfix_dkim; do
    if docker volume inspect "$volume" > /dev/null 2>&1; then
        printf 'Refusing to restore: Docker volume %s already exists.\n' "$volume" >&2
        exit 1
    fi
done

cd "$infra_dir"
install -m 600 "${backup_dir}/infra.env" .env
docker compose up -d --wait postgres redis

gunzip -c "${backup_dir}/database.sql.gz" | docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" "$POSTGRES_DB"'

docker volume create lab_cps_photos > /dev/null
docker run --rm -v lab_cps_photos:/data -v "${backup_dir}:/backup:ro" alpine tar xzf /backup/photos.tar.gz -C /data
docker volume create lab_postfix_dkim > /dev/null
docker run --rm -v lab_postfix_dkim:/data -v "${backup_dir}:/backup:ro" alpine tar xzf /backup/postfix-dkim.tar.gz -C /data

docker compose pull
docker compose run --rm cps-app php artisan migrate --force
docker compose up -d
docker compose ps
