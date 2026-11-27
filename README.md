# dsh-to-docker

Docker-образ [DeepSeek Harness (`dsh`)](https://github.com/deepseek-ai/deepseek-harness) — Web UI и CLI агентного харнесса DeepSeek в контейнере. Образ собирается из готового npm-пакета `@deepseek-ai/dsh`; здесь только упаковка, исходники dsh в репозитории отсутствуют.

- Образ: [`muryginds/dsh`](https://hub.docker.com/r/muryginds/dsh) — теги `latest`, `<версия>`, суффикс `-minimal` для облегчённого набора инструментов
- dsh — developer preview: ломающие изменения между версиями возможны, каждая версия образа пиннит свою версию dsh

## Быстрый старт

```sh
git clone https://github.com/Muryginds/dsh-to-docker.git
cd dsh-to-docker
cp .env.example .env      # впишите DEEPSEEK_API_KEY
mkdir -p workspace        # сюда монтируются проекты агента
docker compose up -d
docker compose logs -f dsh
```

Дождитесь строки `dsh web: http://localhost:3080/?token=…` и откройте ссылку: токен живёт до перезапуска контейнера, браузер обменяет его на cookie на 30 дней. Предупреждение `no sandbox runner works in this container` в логах нормально — см. [Sandbox](#sandbox). Без compose:

```sh
docker run -d --name dsh -p 3080:3080 -v dsh-data:/data -v "$PWD/workspace:/workspace" \
  -e DEEPSEEK_API_KEY muryginds/dsh:latest
docker logs dsh
```

| Путь в контейнере | Что там | Куда монтировать |
|---|---|---|
| `/data` | `DSH_HOME=/data/.dsh` (профили, сессии, ключи, настройки, логи), `DSH_AGENTS_HOME=/data/.agents` | named volume |
| `/workspace` | Корень workspace по умолчанию и рабочая директория команд агента | каталог с проектом |

Контейнер работает от `node` (uid 1000): смонтированные каталоги должны быть доступны этому uid на запись. Любая команда кроме `web` уходит напрямую в `dsh`:

```sh
docker run --rm muryginds/dsh:latest --version
docker run --rm muryginds/dsh:latest headless "перечисли пакеты"   # одноразичная задача
```

## Модель и корпоративный прокси

Ключ вводится в **Settings → Models** (хранится в `/data/.dsh/.credentials.yaml`) или задается переменной `DEEPSEEK_API_KEY`. Формат ключа произвольный — он уходит в заголовке `x-api-key` как есть.

| Прокси | Как подключить |
|---|---|
| Говорит по Messages API (Anthropic-протокол, как `https://api.deepseek.com/anthropic`) | `DEEPSEEK_API_KEY` + `DEEPSEEK_BASE_URL` в `.env` (или в UI). dsh добавит `/v1/messages`; базовый URL — без учётных данных, query и fragment |
| То же, но другие id моделей | Дополнительно список `models` — вариант 1 в [`cordis.patch.example.yml`](cordis.patch.example.yml) |
| Только OpenAI-совместимый | **Settings → Models → Add model provider → Custom model API** (протокол OpenAI Chat Completions или Responses) или вариант 2 в `cordis.patch.example.yml` |

`DEEPSEEK_BASE_URL` читается только из окружения контейнера или `/data/.dsh/.env`, но не из `.env` проекта. Для неофициального endpoint список моделей не запрашивается — используются встроенные `deepseek-flash` и `deepseek-v4-pro`.

## Переменные

Все переменные задаются в `.env` (шаблон — [`.env.example`](.env.example)).

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `DEEPSEEK_API_KEY` | — | Ключ DeepSeek или токен прокси |
| `DEEPSEEK_BASE_URL` | официальный API | Messages-совместимый endpoint |
| `DSH_PORT` / `DSH_HOST_PORT` | `3080` / `3080` | Порт в контейнере / на хосте |
| `DSH_PUBLIC_URL` | `http://localhost:<port>/` | Адрес в ссылке для входа и в `DSH_WEB_URL`; `none` — отключить |
| `DSH_TRUSTED_HOSTS` | — | Хосты (`host` или `host:port` через пробел), с которых разрешён доступ к `/api`: всё, кроме `localhost`, без них получает 403 |
| `DSH_TLS_CERT`, `DSH_TLS_KEY` | — | TLS на listener'е, пути внутри контейнера |
| `DSH_HOST` | авто | IP интерфейса внутри контейнера для `--host` |
| `DSH_PERMISSION_MODE` | авто | `read-only` / `workspace-write` / `danger-full-access`; пусто — авто-выбор, см. [Sandbox](#sandbox) |
| `DSH_TELEMETRY_MODE` | — | `DISABLED` выключает OTel-выгрузку |
| `DSH_PROFILE` | `web` | Профиль dsh |
| `DSH_EXTRA_ARGS` | — | Дополнительные флаги `dsh web` |
| `DSH_IMAGE`, `DSH_TAG`, `DSH_WORKSPACE` | — | Только для `docker compose` |

## Сборка и публикация

Нужны `docker` с buildx и `curl`; `jq` необязателен. Без флагов в терминале скрипты спрашивают версию, набор инструментов, платформы и доп. пакеты; в CI работают молча с значениями по умолчанию (`--yes`).

```sh
./scripts/build.sh                                   # собрать локально (--load), проверка dsh --version
./scripts/publish.sh                                 # собрать и запушить все теги
./scripts/publish.sh --yes --platforms linux/amd64,linux/arm64 --toolset minimal
./scripts/build.sh --dry-run                         # показать команды docker без запуска
```

| Параметр | Значения | По умолчанию |
|---|---|---|
| `--version` | dist-tag npm (`latest`, `next`, `alpha`) или точная версия | `latest` |
| `--toolset` | `full` (git, python3 + pip, build-essential, …) или `minimal` | `full` |
| `--extra-packages` | Дополнительные apt-пакеты через пробел | — |
| `--platforms` | Через запятую; локальная сборка — только первая | `linux/amd64` |
| `--image` | `namespace/name` | `muryginds/dsh` |
| `--node-image`, `--npm-registry` | Базовый образ, реестр npm | `node:24-bookworm-slim`, npmjs |

Теги: `<версия>` плюс по тегу на каждый npm dist-tag, который на неё указывает (`latest`, `next`, `alpha`); для `minimal` добавляется суффикс. Для мультиархитектурной сборки скрипт создаёт buildx-builder `dsh-builder` и не меняет builder по умолчанию. Тот же параметр можно задать переменной окружения `DSH_<ИМЯ>` (`DSH_VERSION`, `DSH_TOOLSET`, `DSH_PLATFORMS`, `DSH_IMAGE`, `DSH_EXTRA_APT_PACKAGES`, …).

## Sandbox

Новые сессии по умолчанию работают в режиме `workspace-write` (запись только в workspace и временные каталоги). На Linux dsh ищет `bwrap`, затем Landlock и, если не работает ни один, не запускает команды вовсе (`SANDBOX_UNAVAILABLE`). В обычном контейнере Docker Desktop не работает ни один: у виртуальной машины нет Landlock в списке LSM, а `bwrap` нужны привилегии.

Поэтому entrypoint при старте проверяет оба раннера. Если ни один не работает и `DSH_PERMISSION_MODE` не задан, образ включается с `danger-full-access` и пишет предупреждение в лог: команды агента выполняются без дополнительных ограничений, изоляцией служит сам контейнер — монтируйте в него только то, что агент может менять. Варианты:

- `DSH_PERMISSION_MODE=workspace-write` (или `read-only`) — запретить авто-выбор; нужен рабочий sandbox, иначе команды не выполняются;
- `--privileged` у контейнера — включает `bwrap`, режим остаётся `workspace-write` (проверено);
- на Linux-хосте Landlock может работать и без привилегий — зависит от ядра и профиля seccomp; entrypoint увидит это сам.

По умолчанию включена выгрузка session-log в DeepSeek (`DSH_TELEMETRY_MODE=DISABLED` выключает OTel-часть; полная настройка — [SAFETY.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/SAFETY.md) и Settings → General).

## Ссылки

- [Документация dsh](https://deepseek-harness.github.io/deepseek-harness/) · [репозиторий](https://github.com/deepseek-ai/deepseek-harness) · [npm](https://www.npmjs.com/package/@deepseek-ai/dsh)
- [Web UI: настройка моделей, workspace, задачи](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/index.md)
- [Провайдеры и кастомные endpoint'ы](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/providers.md)
- [Reverse proxy и публичный доступ](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/public-deployments.md) · [сетевой прокси](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/network-proxy.md)
- [CLI: профили, флаги, плагины](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/cli/README.md) · [справочник по командам](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/cli-help.md)
- [Плагины и индексы](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/plugin-market.md) · [Sandbox](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/sandbox/sandbox-local/README.md)
- [SAFETY.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/SAFETY.md)
