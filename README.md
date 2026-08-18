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
| `.env.example` | форма окружения |

## Схема

Наружу опубликованы только порты Traefik. У остальных сервисов `ports` нет —
они достижимы лишь изнутри compose.

```
:443 ── traefik ─┬─ cps-nginx ── cps-app ──┬── postgres
                 │               cps-queue ─┼── redis
                 └─ cps-client              └── том cps_photos
```

Второй проект добавляется в этот же compose и переиспользует общие сервисы:
`DB_HOST=postgres`, `REDIS_HOST=redis`.
