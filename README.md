# NixOS configuration for oggy

## деплой -  выкладка выкатки

Команду нужно запускать из корня этого репозитория. Она собирает конфигурацию
`oggy`, копирует результат на сервер и активирует его:

```shell
nix run nixpkgs#nixos-rebuild -- switch --flake .#oggy --target-host oggy.home.arpa --sudo
```

## Обновление DNS-записи Cloudflare

```shell
CF_API_TOKEN="$(secret-tool lookup service cloudflare purpose dns zone killeik.net)" flarectl dns create-or-update --zone=killeik.net --name=grafana --type=CNAME --content=server.killeik.net --ttl=1
```
