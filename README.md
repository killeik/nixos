# NixOS configuration for oggy

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

## Конфиги и секреты

Перед первой выкладкой разделить старый `.env` на файлы в
`/home/killeik/selfhost` на oggy (`root:root`, `0600`, вне Git):

| Файл | Переменные |
| --- | --- |
| `caddy.env` | `CLOUDFLARE_API_TOKEN` |
| `miniflux.env` | `DATABASE_URL`, `YOUTUBE_API_KEY` |
| `postgres.env` | `POSTGRES_PASSWORD` |
| `silverbullet.env` | `SB_USER` |

Значения сохранить, дополнительные переменные разнести по сервисам.
Старый `.env` оставить до проверки. Пример: `selfhost/.env.example`.

`selfhost/soularr/config.ini` - начальный шаблон, рабочие настройки живут на сервере.

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
Макет хранится в `dashboards/qingping.json`, период по умолчанию - сутки.

Алерты Grafana описаны в `qingping.nix`: CO2 выше 1500 ppm в течение 10 минут,
влажность ниже 30% или выше 60% в течение 30 минут. Проверка раз в минуту,
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
