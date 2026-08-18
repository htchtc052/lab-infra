# CuratedPhoto — развёртывание

Проект состоит из трёх репозиториев. На сервере они лежат рядом, **имена каталогов
важны** — на них ссылаются пути сборки в `docker-compose.yml`:

```
/srv/curated-photo/
├── backend     ← cps-backend    (Laravel API)
├── frontend    ← cps-client     (Nuxt SSR)
└── infra       ← lab-infra      (этот репозиторий)
```

Postgres и Redis живут на хосте, а не в compose — они общие для всех проектов
на этом VPS. Контейнеры ходят к ним через `host.docker.internal`.

---

## 1. Хост — один раз на сервере

### 1.1 Docker

```bash
curl -fsSL https://get.docker.com | sh
```

### 1.2 Traefik

Traefik ставится отдельно и обслуживает все проекты на сервере. Compose этого
проекта рассчитывает на такой контракт:

| что | значение |
|---|---|
| внешняя docker-сеть | `traefik` |
| entrypoint для HTTPS | `websecure` |
| резолвер сертификатов | `letsencrypt` |

Если Traefik ещё не поднят, сеть создаётся так:

```bash
docker network create traefik
```

### 1.3 Postgres

```bash
sudo -u postgres psql -c "CREATE USER curated_photo WITH PASSWORD 'ПРИДУМАЙ_ПАРОЛЬ';"
sudo -u postgres psql -c "CREATE DATABASE curated_photo OWNER curated_photo;"
```

Postgres должен принимать соединения из docker-сети. В `postgresql.conf`:

```
listen_addresses = 'localhost,172.17.0.1'
```

и в `pg_hba.conf` — строка для docker-подсети:

```
host    curated_photo    curated_photo    172.16.0.0/12    scram-sha-256
```

После правок: `sudo systemctl restart postgresql`.

### 1.4 Redis

В `/etc/redis/redis.conf`:

```
bind 127.0.0.1 172.17.0.1
requirepass ПРИДУМАЙ_ПАРОЛЬ
```

После правок: `sudo systemctl restart redis-server`.

### 1.5 Файрвол

Пункты 1.3 и 1.4 открывают Postgres и Redis на интерфейс docker. Снаружи они
торчать не должны:

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Порты 5432 и 6379 не открываем — доступ к ним только из контейнеров.

### 1.6 Deploy-ключ для приватных репозиториев

```bash
ssh-keygen -t ed25519 -C "vps-deploy" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

Публичный ключ добавить в **каждый** из трёх репозиториев: Settings → Deploy keys
→ Add deploy key, доступ только на чтение. Один и тот же ключ переиспользовать
нельзя — GitHub требует уникальный deploy key на репозиторий, поэтому либо
сгенерируй три ключа с разными именами файлов и опиши их в `~/.ssh/config`, либо
добавь один ключ в аккаунт целиком (Settings → SSH keys), что проще для соло-проекта.

Проверка:

```bash
ssh -T git@github.com
```

---

## 2. Проект

### 2.1 Клонирование

Целевой каталог указывается явно — имена репозиториев и каталогов не совпадают:

```bash
sudo mkdir -p /srv/curated-photo && sudo chown $USER /srv/curated-photo
cd /srv/curated-photo
git clone git@github.com:htchtc052/cps-backend.git backend
git clone git@github.com:htchtc052/cps-client.git  frontend
git clone git@github.com:htchtc052/lab-infra.git   infra
```

### 2.2 Окружение

`.env` — единственный источник правды по боевым значениям, и живёт он **только
на сервере**. В git лежит `.env.example` — он задаёт форму, то есть набор ключей.

```bash
cd /srv/curated-photo/infra
cp .env.example .env
chmod 600 .env
```

Сгенерировать `APP_KEY` и вписать его в `.env`:

```bash
echo "base64:$(openssl rand -base64 32)"
```

Дальше заполнить руками: `API_DOMAIN`, `APP_DOMAIN` и производные от них
`APP_URL`, `FRONTEND_URL`, `SESSION_DOMAIN`, `SANCTUM_STATEFUL_DOMAINS`, а также
`DB_PASSWORD` и `REDIS_PASSWORD` из пунктов 1.3 и 1.4.

> `APP_KEY` продублируй в свой менеджер паролей. Остальные значения
> восстановимы — эти сервисы принадлежат тебе, пароль всегда можно сменить.

### 2.3 Запуск

```bash
cd /srv/curated-photo/infra
docker compose build
docker compose run --rm app php artisan migrate --force
docker compose up -d
```

Проверить:

```bash
docker compose ps
docker compose logs -f --tail=50
```

### 2.4 Обновление

```bash
cd /srv/curated-photo
git -C backend pull --ff-only
git -C frontend pull --ff-only
git -C infra pull --ff-only
cd infra
docker compose build
docker compose run --rm app php artisan migrate --force
docker compose up -d
```

`docker compose up -d` пересоздаёт только изменившиеся контейнеры, так что
команду можно повторять сколько угодно раз.

> Когда в `.env.example` появляется новый ключ, его нужно руками добавить в `.env`
> на сервере — иначе контейнер поднимется без него.

---

## 3. Данные

Всё состояние проекта — это база и том с фотографиями. Код и `.env` к состоянию
не относятся: код в git, `.env` пересоздаётся из `.env.example` за пару минут.

Снять копию:

```bash
pg_dump -U curated_photo -h localhost curated_photo | gzip > ~/curated_photo.sql.gz
docker run --rm -v curated-photo_photo_storage:/data -v ~:/backup alpine \
  tar czf /backup/photo_storage.tar.gz -C /data .
```

Восстановить на новом сервере — после пункта 2.2 и до `migrate`:

```bash
gunzip -c ~/curated_photo.sql.gz | psql -U curated_photo -h localhost curated_photo
docker volume create curated-photo_photo_storage
docker run --rm -v curated-photo_photo_storage:/data -v ~:/backup alpine \
  tar xzf /backup/photo_storage.tar.gz -C /data
```

Фотографии без базы бесполезны — это файлы без владельцев, альбомов и ссылок.
Переносить нужно обе части вместе.
