# CuratedPhoto — развёртывание

Три репозитория лежат на сервере рядом. **Имена каталогов важны** — на них
ссылаются пути сборки в `docker-compose.yml`:

```
/srv/lab/
├── backend     ← cps-backend    (Laravel API)
├── frontend    ← cps-client     (Nuxt SSR)
└── infra       ← lab-infra      (этот репозиторий)
```

Всё остальное — traefik, postgres, redis и сервисы проекта — живёт в одном
compose. На хосте нужен только docker.

---

## 1. Хост

```bash
curl -fsSL https://get.docker.com | sh
```

Если репозитории приватные, серверу нужен доступ к GitHub. Проще всего добавить
один ключ в аккаунт целиком (Settings → SSH keys):

```bash
ssh-keygen -t ed25519 -C "vps" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
ssh -T git@github.com
```

## 2. Проект

Целевой каталог указывается явно — имена репозиториев и каталогов не совпадают:

```bash
mkdir -p /srv/lab && cd /srv/lab
git clone git@github.com:htchtc052/cps-backend.git backend
git clone git@github.com:htchtc052/cps-client.git  frontend
git clone git@github.com:htchtc052/lab-infra.git   infra
```

`.env` — единственный источник правды по боевым значениям, и живёт он **только
на сервере**. В git лежит `.env.example`, задающий набор ключей.

```bash
cd /srv/lab/infra
cp .env.example .env
chmod 600 .env
echo "base64:$(openssl rand -base64 32)"   # APP_KEY
```

Заполнить: `ACME_EMAIL`, домены и производные от них `APP_URL`, `FRONTEND_URL`,
`SESSION_DOMAIN`, `SANCTUM_STATEFUL_DOMAINS`, а также `DB_PASSWORD` и
`REDIS_PASSWORD` — их придумываешь сам, контейнеры создадутся с ними при первом
запуске.

> `APP_KEY` продублируй в менеджер паролей. Остальное восстановимо: эти сервисы
> твои, пароль всегда можно сменить.

Домены `API_DOMAIN` и `APP_DOMAIN` должны A-записями указывать на IP сервера
**до** первого запуска — иначе Let's Encrypt не выдаст сертификат.

```bash
docker compose build
docker compose up -d
docker compose exec cps-app php artisan migrate --force
docker compose ps
```

## 3. Обновление

```bash
cd /srv/lab
git -C backend pull --ff-only
git -C frontend pull --ff-only
git -C infra pull --ff-only
cd infra && docker compose build && docker compose up -d
docker compose exec cps-app php artisan migrate --force
```

`up -d` пересоздаёт только изменившиеся контейнеры — команду можно повторять.

> Появился новый ключ в `.env.example` — добавь его в `.env` на сервере руками.

---

## 4. Пауза и восстановление

Штатный способ — образ в панели Timeweb: он лежит отдельно от сервера и
переживает его удаление.

1. остановить стек, чтобы база попала в снимок в согласованном виде:
   `cd /srv/lab/infra && docker compose stop`
2. снять образ: панель → сервер → Образы;
3. удалить сервер — почасовые списания прекращаются, остаётся ~4 ₽/ГБ в месяц
   за хранение образа;
4. вернуться: создать сервер из образа. Поднимется всё вместе с данными.

> Образы удаляются через 7 дней после блокировки аккаунта за неуплату. Держи
> на балансе небольшую сумму, иначе пауза превратится в потерю.

## 5. Копия данных

Нужна, только если образ недоступен или переезжаешь к другому провайдеру.
Состояние проекта — это база и том с фотографиями.

```bash
cd /srv/lab/infra
docker compose exec -T postgres pg_dump -U curated_photo curated_photo | gzip > ~/db.sql.gz
docker run --rm -v lab_cps_photos:/data -v ~:/backup alpine tar czf /backup/photos.tar.gz -C /data .
```

Восстановить на чистом сервере — после пункта 2, вместо `migrate`:

```bash
cd /srv/lab/infra
docker compose up -d postgres
gunzip -c ~/db.sql.gz | docker compose exec -T postgres psql -U curated_photo curated_photo
docker run --rm -v lab_cps_photos:/data -v ~:/backup alpine tar xzf /backup/photos.tar.gz -C /data
docker compose up -d
```

Фотографии без базы бесполезны — это файлы без владельцев, альбомов и ссылок.
Переносить нужно обе части вместе.
