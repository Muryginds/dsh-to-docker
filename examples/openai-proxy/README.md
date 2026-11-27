# Сценарий: OpenAI-совместимый прокси, доступ только с этого ПК

Для Windows + WSL или Docker Desktop, когда модель доступна через прокси с протоколом OpenAI (`/v1/chat/completions`), а Web UI открывают только локально.

## Что понадобится

- Windows 10/11 с WSL2 (Ubuntu) и Docker Desktop с включённой интеграцией WSL, либо Docker Engine внутри WSL.
- ~3 ГБ свободного места: образ ~1.7 ГБ плюс данные сессий.
- Сеть до Docker Hub и до прокси; внутреннее имя прокси должно резолвиться из WSL и из контейнера.

Проверка в терминале WSL:

```sh
docker version
docker compose version
```

Если `docker` не найден или «permission denied» — включите интеграцию WSL в Docker Desktop (Settings → Resources → WSL Integration) или добавьте пользователя в группу `docker`.

Образ собран под `linux/amd64`. На обычном рабочем ноутбуке он идёт нативно; на Windows on ARM — через эмуляцию, заметно медленнее.

## 1. Получить файлы

```sh
git clone https://github.com/Muryginds/dsh-to-docker.git
cd dsh-to-docker/examples/openai-proxy
```

Дальше все команды выполняются из этого каталога.

## 2. Заполнить `.env`

```sh
cp .env.example .env
mkdir -p ~/projects
```

| Переменная | Значение |
|---|---|
| `ORG_PROXY_API_KEY` | токен прокси |
| `ORG_PROXY_BASE_URL` | адрес прокси без завершающего `/` и без `/chat/completions` |
| `DSH_WORKSPACE` | каталог проектов в файловой системе WSL, например `/home/<user>/projects`; не `/mnt/c` |
| `DSH_HOST_PORT` | порт на этом ПК, по умолчанию `3080` |
| `DSH_TAG` | `0.2.2-rc.5-r2` — фиксированная сборка |

Если меняете `DSH_HOST_PORT`, добавьте `DSH_PUBLIC_URL=http://localhost:<порт>/` — иначе ссылка для входа в логах будет указывать на 3080.

Каталог `DSH_WORKSPACE` создайте заранее: Docker создаёт отсутствующий каталог от root, и контейнер (uid 1000) не сможет в него писать. В шаблоне стоит `DSH_WORKSPACE=./workspace`; для рабочего ПК замените его на абсолютный путь, например `/home/<user>/projects`.

## 3. Описать провайдера

```sh
cp cordis.patch.example.yml cordis.patch.yml
```

Токен и адрес уже берутся из `.env`; в `cordis.patch.yml` остаётся указать id модели и лимиты:

```yaml
- id: llm-pi-ai
  config:
    providers:
      org-proxy:
        displayName: Org Proxy
        apiKeyEnv: ORG_PROXY_API_KEY
        api: openai-completions
        baseURL: !!js process.env.ORG_PROXY_BASE_URL
        compat:
          supportsDeveloperRole: false
          maxTokensField: max_tokens
        models:
          - id: deepseek-v4-flash
            name: DeepSeek V4 Flash
            contextWindow: 1000000
            maxTokens: 131072
```

`maxTokens` — потолок одного ответа, а не размер контекста; почему 128K при окне 1M — в разделе [Контекст и лимит вывода](#контекст-и-лимит-вывода).

`cordis.patch.yml` и `.env` в `.gitignore`: адрес и токен в репозиторий не попадут. Правки подхватываются без перезапуска контейнера.

## 4. Проверить доступ к прокси

```sh
set -a; . ./.env; set +a

curl -sS -o /dev/null -w '%{http_code}\n' "$ORG_PROXY_BASE_URL/models" \
  -H "Authorization: Bearer $ORG_PROXY_API_KEY"

docker run --rm --entrypoint curl "muryginds/dsh:$DSH_TAG" \
  -sS -o /dev/null -w '%{http_code}\n' "$ORG_PROXY_BASE_URL/models" \
  -H "Authorization: Bearer $ORG_PROXY_API_KEY"
```

Ожидается `200`; без токена — `401`. Если из WSL работает, а из контейнера нет, или вместо ответа ошибка сертификата — см. [«Если что-то не работает»](#если-что-то-не-работает).

## 5. Запустить

```sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs -f dsh
```

Дождитесь строки `dsh web: http://localhost:3080/?token=…` и откройте ссылку в браузере Windows: порт опубликован только на `127.0.0.1`, с других устройств он недоступен. Токен живёт до перезапуска контейнера; браузер обменяет его на cookie на 30 дней.

## 6. Первый вход

- Над полем ввода выберите модель **Org Proxy → DeepSeek V4 Flash**. Официальный маршрут DeepSeek без ключа скрыт; выбор запомнится.
- Отправьте тестовый запрос: «Ответь одним словом: работает».
- Селектор **Permissions**: в Docker Desktop нет Landlock, поэтому entrypoint сам включает `danger-full-access` и пишет предупреждение в лог. Команды агента выполняются без внутренней песочницы, а границей служит контейнер: агенту доступны только `/workspace` (ваш каталог проектов) и `/data` (сессии и настройки).

## 7. Ежедневная работа

```sh
docker compose up -d        # запустить
docker compose stop         # остановить, данные сохраняются
docker compose logs --tail=50 dsh
docker compose logs dsh | grep -o 'http://[^ ]*token=[^ ]*' | tail -1
```

Данные dsh (сессии, настройки, ключи) лежат в volume `openai-proxy_dsh-data` и переживают перезапуск и обновление образа. Каталог проектов — на хосте, в `DSH_WORKSPACE`.

## 8. Обновить образ

Новые сборки — неизменяемые теги `<версия>-r<N>`; список: https://hub.docker.com/r/muryginds/dsh/tags. Чтобы перейти на новую:

```sh
# в .env: DSH_TAG=0.2.2-rc.5-r3
docker compose pull
docker compose up -d
```

Откат — вернуть прежний `DSH_TAG` и повторить. Данные не затрагиваются.

## 9. Резервная копия

```sh
docker run --rm -v openai-proxy_dsh-data:/data -v "$PWD":/backup alpine \
  tar czf /backup/dsh-data.tgz -C /data .
```

Восстановление — распаковать в тот же volume при остановленном контейнере.

## Если что-то не работает

**`INVALID_CONFIG` про `supportsDeveloperRole` или `needs a baseURL`** — пустой `ORG_PROXY_BASE_URL` в `.env`.

**Порт занят** (`bind: address already in use`) — смените `DSH_HOST_PORT` и добавьте `DSH_PUBLIC_URL` (см. шаг 2), затем `docker compose up -d`.

**`INVALID_REQUEST` и упоминание `max_tokens`** — прокси не принимает заявленный лимит вывода. Уменьшите `maxTokens` у модели, например до `65536` или `8192`.

**`INVALID_REQUEST` из-за неизвестного поля `store` или `stream_options`** — добавьте в `compat` провайдера:

```yaml
          supportsStore: false
          supportsUsageInStreaming: false
```

**Ответы обрываются** — лимит вывода слишком мал (у модели с рассуждениями на него уходят и рассуждения). Увеличьте `maxTokens`; `contextWindow` при этом должен быть больше него.

**Модель не найдена (`UNKNOWN_MODEL`, 404 от прокси)** — сверьте id модели со списком прокси:

```sh
set -a; . ./.env; set +a
curl -s "$ORG_PROXY_BASE_URL/models" -H "Authorization: Bearer $ORG_PROXY_API_KEY"
```

**Прокси по внутреннему имени не резолвится из контейнера.** Раскомментируйте в `docker-compose.yml` `dns` (DNS организации) или `extra_hosts` (имя и IP):

```yaml
    dns:
      - 10.0.0.53
    # или
    extra_hosts:
      - "proxy.example.com:10.0.0.10"
```

**Ошибка сертификата** (`self-signed certificate in certificate chain`, `unable to get local issuer certificate`) — корпоративный TLS-перехват. Смонтируйте корневой сертификат организации и укажите его Node:

```yaml
    volumes:
      - /home/<user>/certs/corp-ca.crt:/certs/corp-ca.crt:ro
    environment:
      - NODE_EXTRA_CA_CERTS=/certs/corp-ca.crt
```

**Контейнер не стартует или `unhealthy`** — смотрите `docker compose logs dsh`. Если в логе `workspace … is not writable by uid 1000`, проверьте владельца каталога: `sudo chown -R 1000:1000 ~/projects`.

**Конфликт имени `dsh`** — корневой compose из репозитория и этот используют одно имя контейнера. Запускайте что-то одно: `docker rm -f dsh` перед стартом.

**Медленно работают файлы** — каталог проектов должен быть в файловой системе WSL (`/home/...`), а не в `/mnt/c`.

**`toomanyrequests` при `docker compose pull`** — лимит анонимных загрузок Docker Hub; выполните `docker login`.

## Контекст и лимит вывода

`contextWindow` — общее окно модели (вход + выход), `maxTokens` — потолок одного ответа; он уходит как `max_tokens` в каждом запросе.

У DeepSeek V4 Flash окно 1M и рекомендуемый максимум вывода до 384K (для режимов high/max). Но dsh резервирует `maxTokens` из окна при автоматическом сжатии истории: порог сжатия = min(0.8 × `contextWindow`, `contextWindow` − `maxTokens` − 64K). Поэтому:

| `maxTokens` | История сжимается на |
|---|---|
| 32K | 800K |
| 128K | 800K |
| 384K | 541K |

Для окна 1M разумный выбор — **131072 (128K)**: запас на рассуждения почти максимальный, а история по-прежнему сжимается только на 800K. Если прокси не принимает такой `max_tokens`, уменьшите до `65536`. Поднимать до `384000` имеет смысл только если на режиме **max** ответы обрываются, и тогда сжатие истории начнётся раньше.

## Управление рассуждениями

По умолчанию модель думает так, как настроено на стороне прокси. Чтобы получать меню **Effort** (`off` / `high` / `max`), добавьте в `compat` провайдера `thinkingFormat: deepseek`, а в модель — `reasoningEfforts`:

```yaml
        compat:
          # добавьте к существующим полям:
          thinkingFormat: deepseek
        models:
          - id: deepseek-v4-flash
            # добавьте к существующим полям:
            reasoningEfforts:
              off:
              high: high
              max: max
```

Прокси должен передавать параметр `thinking` в DeepSeek; при ошибке `INVALID_REQUEST` верните как было.

Если прокси говорит по Messages API (Anthropic-протокол), файл провайдера не нужен — достаточно `DEEPSEEK_API_KEY` и `DEEPSEEK_BASE_URL` в корневом [`.env.example`](../../.env.example).
