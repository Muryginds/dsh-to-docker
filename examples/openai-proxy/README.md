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

Если прокси говорит по Messages API (Anthropic-протокол), файл провайдера не нужен — достаточно `DEEPSEEK_API_KEY` и `DEEPSEEK_BASE_URL` в корневом [`.env.example`](../../.env.example).
