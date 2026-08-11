# NixOS configuration for oggy

## деплой -  выкладка выкатки

Команду нужно запускать из корня этого репозитория. Она собирает конфигурацию
`oggy`, копирует результат на сервер и активирует его:

```shell
nix run nixpkgs#nixos-rebuild -- switch --flake .#oggy --target-host oggy.local --sudo
```
