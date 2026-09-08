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

## Обновление DNS-записи Cloudflare

```shell
CF_API_TOKEN="$(secret-tool lookup service cloudflare purpose dns zone killeik.net)" flarectl dns create-or-update --zone=killeik.net --name=grafana --type=CNAME --content=server.killeik.net --ttl=1
```
