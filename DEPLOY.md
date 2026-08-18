# Развёртывание

Каталоги на сервере — их имена жёстко связаны с путями сборки в `docker-compose.yml`:

```
/srv/lab/
├── backend     ← cps-backend
├── frontend    ← cps-client
└── infra       ← lab-infra
```

## Запуск

```bash
curl -fsSL https://get.docker.com | sh

mkdir -p /srv/lab && cd /srv/lab
git clone git@github.com:htchtc052/cps-backend.git backend
git clone git@github.com:htchtc052/cps-client.git  frontend
git clone git@github.com:htchtc052/lab-infra.git   infra

cd infra
cp .env.example .env && chmod 600 .env
echo "base64:$(openssl rand -base64 32)"
```

Заполнить `.env`. `A`-записи `API_DOMAIN` и `APP_DOMAIN` должны указывать на сервер
до первого запуска — иначе Let's Encrypt не выдаст сертификат.

```bash
docker compose build
docker compose up -d
docker compose exec cps-app php artisan migrate --force
```

## Обновление

```bash
cd /srv/lab
git -C backend pull --ff-only
git -C frontend pull --ff-only
git -C infra pull --ff-only
cd infra && docker compose build && docker compose up -d
docker compose exec cps-app php artisan migrate --force
```

Новый ключ в `.env.example` нужно добавить в `.env` на сервере руками.

## Копия данных

```bash
cd /srv/lab/infra
docker compose exec -T postgres pg_dump -U curated_photo curated_photo | gzip > ~/db.sql.gz
docker run --rm -v lab_cps_photos:/data -v ~:/backup alpine tar czf /backup/photos.tar.gz -C /data .
```

Восстановление на чистом сервере — вместо `migrate`:

```bash
docker compose up -d postgres
gunzip -c ~/db.sql.gz | docker compose exec -T postgres psql -U curated_photo curated_photo
docker run --rm -v lab_cps_photos:/data -v ~:/backup alpine tar xzf /backup/photos.tar.gz -C /data
docker compose up -d
```
