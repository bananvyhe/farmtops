# News Translation Runbook

Цель: быстро отличать нормальный фон очереди от реального залипания перевода.

## Что считается нормой

- `NewsTranslatePendingArticlesJob` и `NewsTranslateArticleJob` работают как цепочка на одну статью за раз.
- `NewsTranslateArticleJob` ставит watchdog через `perform_in(1.minute)`.
- `NewsTranslationRecoveryJob` нужен как one-shot recovery на старте/вручную, а не как регулярный cron.
- После завершения перевода pipeline переходит к идентификации игр.

## Что обычно ломается

- В `Sidekiq` видны повторные job'ы, но они на самом деле приходят из watchdog/recovery, а не из отдельной новой задачи.
- У процесса `sidekiq` задан неправильный `NEWS_TRANSLATOR_BASE_URL`, и он ходит в `127.0.0.1:19191` вместо живого хоста.
- В окружении задан URL, который формально присутствует, но недоступен из контейнера. В этом случае нужен health-based fallback.
- Redis lock `news:translation:pending_articles_lock` может остаться stale, и очередь больше не стартует.

## Быстрая проверка

1. Посмотреть, есть ли в логах `Translator unavailable: Failed to open TCP connection to 127.0.0.1:19191`.
2. Проверить, какой `NEWS_TRANSLATOR_BASE_URL` видит именно `sidekiq`, а не только shell на хосте.
3. Проверить `host.docker.internal:19191/health` из контейнера `sidekiq`.
4. Проверить, не висит ли lock в Redis.
5. Посмотреть, не осталась ли одна статья в `translating` без обновления `translation_started_at`.

## Безопасные действия

- Не считать повтор watchdog/recovery багом без проверки логов.
- Не править сам translator, если его health и translate endpoint отвечают.
- Сначала проверять окружение `sidekiq`, потом уже сеть и только после этого код.
- Если URL в конфиге мёртвый, не застревать на нём: нужен fallback на живой endpoint.

## История кейсов

- `127.0.0.1:19191` в production-sidekiq оказался ложным адресом, если контейнер должен ходить на host tunnel.
- Recovery долго ждал stalled `translating` статьи, поэтому очередь выглядела мёртвой.
- Необработанное исключение в `NewsTranslateArticleJob` раньше могло приводить к повторному retry одной и той же статьи.
