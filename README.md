# NixOS / oggy

## Устройства

| Устройство | Адрес | Назначение / конфигурация |
| --- | --- | --- |
| oggy | `oggy.home.arpa` / `192.168.1.2` | Домашний сервер: [hosts/oggy](hosts/oggy) |
| selfhost-remote | - | Заготовка QEMU VM: [hosts/selfhost-remote](hosts/selfhost-remote) |
| OpenWrt | `192.168.1.1` | Роутер: [openwrt](openwrt) |
| sparky | `sparky.home.arpa` | Мониторинг через node-exporter |
| Qingping CGDN1 | MQTT через oggy | Датчик воздуха: [smarthome.nix](hosts/oggy/selfhost/smarthome.nix) |

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
