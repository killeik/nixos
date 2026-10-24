# NixOS / oggy

Названия коммитов и MR должны смешно и немного странно рассказывать об изменениях моими словами, без абстракций и повторения одних и тех же образов.

## Устройства

| Устройство | Адрес | Конфигурация |
| --- | --- | --- |
| oggy | `oggy.home.arpa` | [NixOS](hosts/oggy) |
| OpenWrt | `openwrt.home.arpa` | [OpenWrt](openwrt) |
| sparky | `sparky.home.arpa` | [node-exporter](hosts/sparky/prometheus-node-exporter) |

Внешние хосты: [selfhost-remote](hosts/selfhost-remote) и [nuxt-de](hosts/nuxt-de).

## Подключить pre-commit

```sh
git config core.hooksPath .githooks
```

## Обновление и деплой oggy

```sh
nix flake update
nix run nixpkgs#nixos-rebuild -- switch --flake .#oggy --target-host oggy.home.arpa --sudo
```

Обновить контейнер:

```sh
ssh oggy.home.arpa 'sudo systemctl restart docker-<name>.service'
```

[Резервные копии и восстановление](docs/backups.md).

## DNS Cloudflare

```sh
export CLOUDFLARE_API_TOKEN="$(passage show api.cloudflare.com/killeik.net.dns-api-token)"

# Создать
cf dns records create --zone killeik.net \
  --body '{"type":"CNAME","name":"grafana.killeik.net","content":"server.killeik.net","ttl":1}'

# Изменить
cf dns records edit <record-id> --zone killeik.net \
  --body '{"content":"server.killeik.net","ttl":1}'
```

[Архив решений](docs/archive/2026-10-21-maintenance.md).
