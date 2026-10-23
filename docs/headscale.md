# Headscale на oggy

Native Headscale 0.29.5 управляет обычными клиентами Tailscale. HTTPS и DERP
идут через Caddy на `headscale.killeik.net`, MagicDNS использует
`mesh.killeik.net`. Собственный embedded DERP - единственный relay; публичные
relay Tailscale отключены. Отказ oggy лишает сеть control server и relay,
хотя существующие прямые соединения могут продолжить работу.

## До деплоя

- Создать DNS-only A/AAAA `headscale.killeik.net` на реальный внешний адрес.
  Cloudflare Proxy и Tunnel не поддерживают нужный control-протокол.
  DNS-01 для сертификатов Caddy при этом остается пригодным.
- Обеспечить внешний TCP 443 до Caddy и UDP 3478 до oggy для STUN.
  При NAT нужен port forwarding; при CGNAT одного проброса недостаточно.
  TCP 80 нужен для HTTP captive-portal endpoint `/generate_204`.
- Проверить доступ с внешней сети, включая hairpin/split DNS для LAN.
  На момент подготовки MR `server.killeik.net` возвращал `192.168.1.2`:
  такой CNAME не обеспечит подключение извне.

В MR нет изменений DNS, роутера или клиентов. Перед выкладкой учесть другие
уже развернутые PR: сборка одной этой ветки не должна откатить их конфигурацию.

## Устройство

`headscale.nix` включает native systemd service. Backend слушает
`192.168.1.2:8085`; firewall пускает к нему только Docker bridge selfhost.
Вся эта сеть считается доверенной для forwarded client IP. Caddy перезаписывает
`True-Client-IP` и `X-Real-IP`, проксирует обычные запросы и Upgrade для
control/DERP. Незашифрованный backend наружу не публикуется.

Метрики и debug endpoint доступны только на `127.0.0.1:9091`, Prometheus
опрашивает job `headscale`. TCP gRPC задан на loopback, insecure gRPC выключен.
Локальное администрирование идет через `/run/headscale/headscale.sock`:
доступ к socket равнозначен администрированию сети, использовать `sudo`.

Ключи Noise/DERP и SQLite с WAL создаются сервисом в `/var/lib/headscale`.
В Git и Nix store секретов нет. OIDC, дополнительного web UI и API keys нет.
Без policy-файла зарегистрированные узлы имеют доступ друг к другу.
Subnet routes и exit nodes автоматически не включаются.

## Первое подключение после согласованного деплоя

На oggy создать пользователя:

```shell
sudo headscale users create killeik
sudo headscale users list
```

На клиенте с установленным Tailscale:

```shell
sudo tailscale up --login-server https://headscale.killeik.net
```

Открыть напечатанную ссылку и взять Auth ID. На oggy подтвердить узел:

```shell
sudo headscale auth register --user killeik --auth-id <AUTH_ID>
sudo headscale nodes list
```

Для подключения без браузера можно создать одноразовый ключ. Здесь `--user`
принимает числовой ID из `users list`, а не имя:

```shell
sudo headscale preauthkeys create --user <USER_ID> --expiration 1h
```

На клиенте:

```shell
sudo tailscale up --login-server https://headscale.killeik.net --authkey <PREAUTH_KEY>
```
Ключ не сохранять в репозитории или чатах. Срок ключа ограничивает
регистрацию, не срок жизни уже зарегистрированного узла. По умолчанию
Headscale не задает срок истечения узла.

## Проверка

```shell
sudo systemctl status headscale.service --no-pager
curl --fail https://headscale.killeik.net/health
curl --fail http://headscale.killeik.net/generate_204
curl --fail http://127.0.0.1:9091/metrics
sudo headscale nodes list
# На двух подключенных клиентах:
tailscale status
tailscale netcheck
tailscale ping <peer-name>
```

Проверить регистрацию с внешней сети и передачу через DERP, когда прямое
соединение недоступно. Успех `/health` сам по себе не проверяет Upgrade,
внешний STUN, NAT или работу клиента. В `netcheck` должен появиться регион Oggy.

## Копии и восстановление

Перед root snapshot helper проверяет логическую копию `headscale.sqlite`.
Отсутствующая/поврежденная БД блокирует backup и pruning. После первого запуска
Headscale проверить backup до следующего таймера.

Root snapshot содержит весь `/var/lib/headscale`, включая Noise и DERP keys.
При восстановлении остановить `headscale.service`, сохранить текущее состояние,
восстановить ключи и совместимую БД из выбранной копии с владельцем
`headscale:headscale`. При замене БД логическим dump удалить старые WAL/SHM
только у остановленного сервиса. Проверить SQLite integrity перед запуском.
Не подменять ключи свежесозданными: это меняет идентичность сервера.
Общая процедура и ограничения локальных копий: [backups.md](backups.md).

Удаление модуля останавливает сервер, но не является миграцией клиентов
обратно в Tailscale SaaS. Данные до проверки восстановления не удалять.

## Источники

- [Headscale 0.29.5 config](https://github.com/juanfont/headscale/blob/v0.29.5/config-example.yaml)
- [Reverse proxy](https://github.com/juanfont/headscale/blob/v0.29.5/docs/ref/integration/reverse-proxy.md)
- [Embedded DERP](https://github.com/juanfont/headscale/blob/v0.29.5/docs/ref/derp.md)
- [Регистрация клиентов](https://github.com/juanfont/headscale/blob/v0.29.5/docs/usage/getting-started.md)
