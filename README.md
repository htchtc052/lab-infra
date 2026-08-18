# lab-infra

Развёртывание проекта **CuratedPhoto** — сервиса для отобранных фотоальбомов
с публичными ссылками на отдельные снимки.

| репозиторий | что внутри |
|---|---|
| [cps-backend](https://github.com/htchtc052/cps-backend) | Laravel API, обработка изображений, очереди |
| [cps-client](https://github.com/htchtc052/cps-client) | Nuxt SSR, интерфейс |
| **lab-infra** | этот репозиторий: compose и инструкция |

## Состав

| файл | назначение |
|---|---|
| `docker-compose.yml` | четыре сервиса: `app` (php-fpm), `nginx-api`, `queue`, `client` |
| `.env.example` | форма окружения — какие ключи обязаны быть заполнены |
| [`DEPLOY.md`](DEPLOY.md) | подготовка хоста и запуск проекта |

## Схема

Postgres и Redis работают на хосте и общие для всех проектов VPS. Наружу
торчит только Traefik, который терминирует TLS и разводит два домена: API и
фронтенд. Оригиналы фотографий лежат в docker-томе, а не в образе.

```
Traefik ──┬── nginx-api ── app (php-fpm) ──┬── Postgres (хост)
          │                                ├── Redis (хост)
          └── client (Nuxt SSR)            └── том photo_storage
                                    queue ─┘
```

Запуск — см. [DEPLOY.md](DEPLOY.md).
