# NixOS / oggy

## Устройства

| Устройство | Адрес | Назначение / конфигурация |
| --- | --- | --- |
| oggy | `oggy.home.arpa` / `192.168.1.2` | Домашний сервер: [hosts/oggy](hosts/oggy) |
| selfhost-remote | - | Заготовка QEMU VM: [hosts/selfhost-remote](hosts/selfhost-remote) |
| OpenWrt | `192.168.1.1` | Роутер: [openwrt](openwrt) |
| sparky | `sparky.home.arpa` | Мониторинг через node-exporter |
| Qingping CGDN1 | MQTT через oggy | Датчик воздуха: [smarthome.nix](hosts/oggy/selfhost/smarthome.nix) |

## Работа с репозиторием

Ветки называть по фиче и создавать от `main`, если нет явной зависимости от другой задачи.
Подключить проверки перед коммитом (один раз после клонирования):

```sh
git config core.hooksPath .githooks
```

Хук запускает `nix fmt -- --ci` и `nix flake check`.

## Обновление и деплой oggy

Из корня репозитория:

```sh
nix flake update
nix run nixpkgs#nixos-rebuild -- switch --flake .#oggy --target-host oggy.home.arpa --sudo
```

Проверка после выкладки:

```sh
ssh oggy.home.arpa 'systemctl --failed; sudo docker ps'
```

Обновить образ контейнера, если сервис не перезапустился при выкладке
(заменить `<name>`):

```sh
ssh oggy.home.arpa 'sudo systemctl restart docker-<name>.service'
```

## Диагностика oggy

```sh
ssh oggy.home.arpa
systemctl --failed
sudo journalctl -u <service> -n 100 --no-pager
sudo docker logs --tail 100 <container>
sudo btrfs filesystem usage /
```

[Резервные копии и восстановление](docs/backups.md).

## DNS Cloudflare

Токен из passage и поиск записи:

```sh
export CLOUDFLARE_API_TOKEN="$(passage show api.cloudflare.com/killeik.net.dns-api-token)"
cf dns records list --zone killeik.net --name grafana.killeik.net
```

Создать новую CNAME:

```sh
cf dns records create --zone killeik.net \
  --body '{"type":"CNAME","name":"grafana.killeik.net","content":"server.killeik.net","ttl":1}'
```

Изменить существующую (подставить ID из `list`):

```sh
cf dns records edit <record-id> --zone killeik.net \
  --body '{"content":"server.killeik.net","ttl":1}'
```

[Архив решений](docs/archive/2026-10-21-maintenance.md).
