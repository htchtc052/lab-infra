# lab-infra

Зонтик для проектов на одном VPS. Сейчас здесь **CuratedPhoto** — сервис для
отобранных фотоальбомов с публичными ссылками на отдельные снимки.

| репозиторий | что внутри |
|---|---|
| [cps-backend](https://github.com/htchtc052/cps-backend) | Laravel API, обработка изображений, очереди |
| [cps-client](https://github.com/htchtc052/cps-client) | Nuxt SSR, интерфейс |
| **lab-infra** | этот репозиторий: compose и инструкция |

## Состав

| файл | назначение |
|---|---|
| `docker-compose.yml` | общий слой (traefik, postgres, redis) и сервисы проекта `cps-*` |
| `.env.example` | форма окружения — какие ключи обязаны быть заполнены |
| [`DEPLOY.md`](DEPLOY.md) | развёртывание, обновление, пауза и копия данных |

## Схема

Наружу торчит только Traefik: он терминирует TLS и разводит два домена — API и
фронтенд. Postgres и Redis доступны лишь из внутренней сети. Оригиналы
фотографий лежат в docker-томе, а не в образе.

```
          ┌─ edge ───────────────┐   ┌─ internal ──────────────┐
:443 ── traefik ─┬─ cps-nginx ───────── cps-app ──┬── postgres
                 │                     cps-queue ─┼── redis
                 └─ cps-client                    └── том cps_photos
```

Второй проект добавляется в этот же compose и переиспользует общие сервисы:
`DB_HOST=postgres`, `REDIS_HOST=redis`.

Запуск — см. [DEPLOY.md](DEPLOY.md).
