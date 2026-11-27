# Сценарий: OpenAI-совместимый прокси, доступ только с этого ПК

Для Windows + WSL или Docker Desktop, когда модель доступна через прокси с протоколом OpenAI (`/v1/chat/completions`), а Web UI открывают только локально.

```sh
cd examples/openai-proxy
cp .env.example .env                      # впишите токен прокси
cp cordis.patch.example.yml cordis.patch.yml   # адрес прокси и id модели
docker compose up -d
docker compose logs -f dsh                # дождитесь dsh web: http://localhost:3080/?token=…
```

Откройте ссылку из логов. При первом запуске выберите модель провайдера **Org Proxy** в списке над полем ввода — официальный маршрут DeepSeek без ключа скрыт, и этот выбор запомнится как модель по умолчанию.

| Что | Где |
|---|---|
| Токен прокси | `.env`, переменная `ORG_PROXY_API_KEY` |
| Адрес прокси, модель, лимиты | `cordis.patch.yml` |
| Проекты агента | `DSH_WORKSPACE` в `.env` — каталог внутри файловой системы WSL |
| Данные dsh (сессии, настройки) | volume `openai-proxy_dsh-data` |
| Доступ | только `127.0.0.1:3080` на хосте |

Смена правок в `cordis.patch.yml` подхватывается без перезапуска. Вместо файла провайдер можно добавить в UI: **Settings → Models → Add model provider → Custom model API**.

## Если что-то не работает

**Первый запрос падает с `INVALID_REQUEST` и упоминанием `max_tokens`** — прокси не принимает заявленный лимит вывода. Уменьшите `maxTokens` у модели (например, до `8192`).

**Ответы обрываются** — лимит вывода слишком мал (у модели с рассуждениями на него уходят и рассуждения). Увеличьте `maxTokens`; `contextWindow` при этом должен быть больше него.

**Модель не найдена (`UNKNOWN_MODEL`, 404 от прокси)** — сверьте id модели со списком прокси: `curl -s <baseURL>/models -H "Authorization: Bearer <токен>"`.

**Прокси по внутреннему имени.** Имя должно резолвиться из WSL и из контейнера; без ключа ожидается ответ `401`:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' https://<proxy>/v1/models
docker run --rm --entrypoint curl muryginds/dsh:latest -sS -o /dev/null -w '%{http_code}\n' https://<proxy>/v1/models
```

Если из контейнера имя не резолвится, раскомментируйте в `docker-compose.yml` `dns` (внутренний DNS организации) или `extra_hosts` (имя и IP).

## Управление рассуждениями

По умолчанию модель думает так, как настроено на стороне прокси. Чтобы получать меню **Effort** (`off` / `high` / `max`), добавьте в модель `reasoningEfforts`, а на уровень провайдера — `compat.thinkingFormat: deepseek` (прокси должен передавать параметр `thinking` в DeepSeek; при ошибке `INVALID_REQUEST` верните как было):

```yaml
        compat:
          supportsDeveloperRole: false
          maxTokensField: max_tokens
          thinkingFormat: deepseek
        models:
          - id: deepseek-v4-flash
            name: DeepSeek V4 Flash
            contextWindow: 128000
            maxTokens: 32768
            reasoningEfforts:
              off:
              high: high
              max: max
```

Если прокси говорит по Messages API (Anthropic-протокол), файл провайдера не нужен — достаточно `DEEPSEEK_API_KEY` и `DEEPSEEK_BASE_URL` в корневом [`.env.example`](../../.env.example).
