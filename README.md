# NixOS configuration for oggy

## Правила работы агентов

Каждую задачу вести в отдельной ветке `agent/<task>`. Если текущая ветка уже
относится к этой задаче, продолжать ее. В `main` напрямую не коммитить.
Перед `nix flake check` и сборкой добавлять новые файлы задачи в Git через
`git add -- <paths>`, чтобы обычный Git-flake видел их. Не обходить проблему
через `path:.`, временные копии flake или overlays старой системы.

Перед staging проверять diff на секреты и локальные данные. Не использовать
слепой `git add .`: добавлять все относящиеся к задаче исходники и документацию,
но не env с реальными значениями, дампы, snapshots, логи и build outputs.
Чужие незавершенные изменения включать только по явному запросу пользователя.

Перед коммитом выполнить `nix fmt -- --ci`, `nix flake check` и сборку
измененного target. Если задача меняет runtime, проверить его на целевом хосте.
После проверок коммитить изменения, пушить ветку в `origin` и создавать PR
для ревью через `gh pr create`, либо обновлять существующий PR этой задачи.
Для этих действий отдельное подтверждение не требуется. В конце сообщать URL
PR и результаты проверок. Не мержить PR и не делать force-push без запроса.
Если доступны инструменты T3, сразу привязывать PR через `link_pull_request`.

## Обновления и деплой

По умолчанию нужны свежие версии всего: обновлять flake inputs, пакеты и
Docker-образы при обслуживании и выкладке. Использовать `nixos-unstable`,
для образов сохранять `pull = "always"` и актуализировать версионные теги.
Мажорные обновления с миграцией данных проводить с резервной копией.
`system.stateVersion` автоматически не повышать: это совместимость данных.

Из корня репозитория:

```shell
nix flake update
nix flake check
nix run nixpkgs#nixos-rebuild -- switch --flake .#oggy --target-host oggy.home.arpa --sudo
```

`pull = "always"` обновляет образ при старте контейнера. Если при выкладке
контейнер не перезапустился, обновить его через соответствующий `docker-*.service`.

Codex CLI в контейнере `codex` установлен пользователем через npm в
`/home/codex/.local`, вне Nix. Обновлять его можно в T3 через
`Settings -> Providers -> Update now`; текущий CLI-логин и история сохраняются.
Первичная установка от пользователя `codex`:

```shell
npm config set prefix "$HOME/.local"
npm install --global @openai/codex@latest
```

T3 использует официальный nightly runtime и штатную пользовательскую службу
`t3code.service` в контейнере `codex`. Nix задает зависимости и drop-in, а T3
управляет своей версией. Обновление: `t3 update --channel nightly` от пользователя
`codex`, либо remote update из T3. Перезапуск выполняется по запросу пользователя.
Установка, проверка и откат: [docs/t3-runtime.md](docs/t3-runtime.md).

Ежедневные снимки root и codex обслуживает btrbk: 7 дней, 4 недели, 3 месяца.
Перед снимками проверяются логические копии Forgejo, Grafana и Miniflux.
Схема хранения и восстановление: [docs/backups.md](docs/backups.md).
Nix GC запускается еженедельно и удаляет поколения старше 30 дней.

## Структура

`flake.nix` выбирает хост. `hosts/oggy/default.nix` содержит настройки хоста
и общие параметры в `_module.args.oggy`; модули запрашивают `{ oggy, ... }`
без импорта отдельного values-файла. Эти параметры используются в настройках,
а не при вычислении `imports`. Внутри контейнера они доступны через внешний scope.

В `hosts/oggy/selfhost/` находятся сервисы oggy: Docker stack в `default.nix`,
мониторинг, `smarthome.nix`, контейнер Codex и резервные копии.
Caddyfile, Grafana dashboards и начальный Soularr config лежат рядом с сервисами.
Runtime state по-прежнему находится на сервере в `/home/killeik/selfhost`.

`hosts/selfhost-remote/default.nix` - заготовка будущей QEMU VM, а не копия
сервисов oggy. Перед использованием проверить `/dev/sda`, `ens3`, доступ
и набор сервисов. Имя flake target `selfhost-remote` сохранено; disko не запускать
по шаблонному устройству без проверки конкретной машины.

История решений: [docs/archive/2026-10-21-maintenance.md](docs/archive/2026-10-21-maintenance.md).
Архив фиксирует контекст на дату обсуждения; последующие решения могут отличаться.

## Конфиги и секреты

Подготовлен выключенный по умолчанию sops-nix. Bootstrap, миграция и
восстановление: [docs/secrets.md](docs/secrets.md).

Рабочие env-файлы находятся в `/home/killeik/selfhost` на oggy
(`root:root`, `0600`, вне Git):

| Файл | Переменные |
| --- | --- |
| `caddy.env` | `CLOUDFLARE_API_TOKEN` |
| `miniflux.env` | `DATABASE_URL`, `YOUTUBE_API_KEY` |
| `postgres.env` | `POSTGRES_PASSWORD` |
| `silverbullet.env` | `SB_USER` |

Общий `.env` больше не используется. При восстановлении сначала создать эти
файлы с согласованными значениями, затем запускать сервисы. Шаблон имен
переменных: `hosts/oggy/selfhost/.env.example`. Рабочие значения брать из резервной копии.

Форматировать Nix-файлы командой `nix fmt`, проверять формат - `nix fmt -- --ci`.

`hosts/oggy/selfhost/soularr/config.ini` - начальный шаблон, рабочие настройки живут на сервере.

## Qingping Air Monitor Lite

CGDN1 подключен к `Smetankovy` по WPA2 и к Mosquitto на `192.168.1.2:1883`.
Показания публикуются в `qingping/ccb5d1327498/up`, команды отправляются в
`qingping/ccb5d1327498/down`. MQTT-пользователь `qingping` имеет доступ только
к `qingping/ccb5d1327498/#`.

Секреты находятся на oggy в `/var/lib/qingping/` (`root:root`, каталог `0700`,
файлы `0600`): `mqtt-password` используется Mosquitto, `link-token` нужен
для повторной локальной настройки по BLE. В Git их не добавлять.

На OpenWrt правило `firewall.qingping_mqtt` разрешает только TCP от Wi-Fi MAC
`cc:b5:d1:32:74:98` из зоны `guest` к `192.168.1.2:1883` в зоне `lan`.

`qingping-exporter` читает MQTT и отдает метрики на `127.0.0.1:9641`.
Его отдельный пользователь `qingping-metrics` имеет только чтение топика
показаний. Пароль хранится в `/var/lib/qingping/metrics-password` (`root:root`,
`0600`) и передается через systemd credentials.

Таймер `qingping-reporting` раз в 50 минут продлевает часовую сессию отчетов
с интервалом 60 секунд. Retained-команда восстанавливает отчеты при
переподключении монитора. Prometheus опрашивает сборщик каждые 15 секунд;
свежесть показаний считается по времени приема MQTT, так как часы датчика
могут быть не синхронизированы.

Дашборд: `http://192.168.1.2:3000/d/qingping-air` или
`https://grafana.killeik.net/d/qingping-air`. Используется обычный вход Grafana.
Макет хранится в `hosts/oggy/selfhost/grafana/dashboards/qingping.json`, период по умолчанию - сутки.

Алерты Grafana описаны в `hosts/oggy/selfhost/smarthome.nix`: CO2 выше 1500 ppm в течение 10 минут,
влажность ниже 35% или выше 55% в течение 30 минут. Проверка раз в минуту,
уведомления идут в Telegram при срабатывании и завершении, повтор - через 4 часа.
Отсутствие данных не вызывает эти алерты.

Telegram-настройки хранятся на oggy в `/var/lib/qingping/telegram.env`
(`root:root`, `0600`): `QINGPING_TELEGRAM_TOKEN` и `QINGPING_TELEGRAM_CHAT_ID`.
Grafana получает их через systemd `EnvironmentFile`; значения не добавлять
в Nix-конфигурацию или Git. После изменения файла перезапустить Grafana.

## Обновление DNS-записи Cloudflare

```shell
CF_API_TOKEN="$(secret-tool lookup service cloudflare purpose dns zone killeik.net)" flarectl dns create-or-update --zone=killeik.net --name=grafana --type=CNAME --content=server.killeik.net --ttl=1
```
