# T3 runtime on oggy

T3 работает в контейнере `codex` от пользователя `codex` (UID 1000).
Официальный CLI хранится в `~/.t3/runtime/versions/<version>/t3`, команда
`~/.local/bin/t3` - symlink installer-а. Nix предоставляет nix-ld, зависимости,
linger и drop-in `/etc/systemd/user/t3code.service.d/overrides.conf`.
Nix использует `systemd.user.services.t3code.overrideStrategy = "asDropin"`:
создает только `overrides.conf`, без основного unit и ссылок в `.wants`.
`enable=true` у Nix-опции разрешает генерацию drop-in; автозапуск включает
native installer. Сам `t3code.service` устанавливает и обновляет T3, а не Nix.

Bind остается `0.0.0.0:3773`. Drop-in задает `T3CODE_HOST`, `T3CODE_PORT`,
PATH с `~/.local/bin` и `UMask=0077`; updater не перезаписывает drop-in.
Общие лимиты контейнера (CPU 600%, MemoryHigh 6G, MemoryMax 8G,
MemorySwapMax 0, TasksMax 4096) продолжают ограничивать user service и агентов.
`PRETTY_HOSTNAME=oggy` сохраняет label. Не менять `~/.t3/userdata`,
`~/.codex` или T3 home: там существующие данные, auth и sessions.

## Проверено до handoff

2026-10-20 официальный installer установил
`0.1.1-nightly.20261020.3411` в home пользователя codex. Архив проверен
installer-ом по SHA256SUMS. Unpatched бинарник работает через nix-ld:
`--version`, `service install --help`, `update --help`, `service status`.
Проверка `--version` прошла также с пустым окружением и только HOME/PATH.
`t3 update 0.1.1-nightly.20261020.3411 --channel nightly` сообщил, что версия
уже установлена. Новый сервер не запускался, прежний system `t3.service`
оставался active. Endpoint возвращал label `oggy` и environmentId
`e7958b5c-4354-4f46-9a55-994bcf4cf7d1`.

Изучены [installer](https://t3.codes/install.sh) и исходники точного release:
[bootService.ts](https://github.com/pingdotgg/t3code/blob/v0.1.1-nightly.20261020.3411/apps/server/src/cloud/bootService.ts),
[serviceLauncher.ts](https://github.com/pingdotgg/t3code/blob/v0.1.1-nightly.20261020.3411/apps/server/src/serviceLauncher.ts),
[update.ts](https://github.com/pingdotgg/t3code/blob/v0.1.1-nightly.20261020.3411/apps/server/src/cli/update.ts),
[selfUpdate.ts](https://github.com/pingdotgg/t3code/blob/v0.1.1-nightly.20261020.3411/apps/server/src/cloud/selfUpdate.ts).
Native install сразу включает и запускает user unit. Remote update UI требует
managed launcher; обычный system unit с `t3 serve` этого не обеспечивает.
Launcher поддерживает trial runtime, backup базы и rollback при неудачном update.
Это установлено по коду; реальный update на другую версию еще не проверен.

## Handoff после Nix switch

Перед switch сохранить обычную резервную копию T3 userdata и доступную
предыдущую NixOS generation. Switch убирает старый system unit и Nix T3,
включает linger, устанавливает drop-in. Не запускать native install до switch:
он сразу займет тот же порт.

Войти на хост:

```shell
ssh -F /dev/null -i /home/killeik/.ssh/amnezia -o BatchMode=yes killeik@192.168.1.2
```

После switch проверить из этой host shell:

```shell
sudo -n nixos-container run codex -- systemctl is-active t3.service
sudo -n nixos-container run codex -- loginctl show-user codex --property=Linger
sudo -n nixos-container run codex -- systemctl is-active user@1000.service
```

Старый unit должен быть inactive/not-found, Linger=yes, user manager active.
Если manager не запустился, проверить его journal до продолжения.
Открыть shell пользователя внутри контейнера:

```shell
sudo -n nixos-container run codex -- runuser -u codex -- env HOME=/home/codex XDG_RUNTIME_DIR=/run/user/1000 PATH=/home/codex/.local/bin:/run/current-system/sw/bin bash
```

В этой user shell:

```shell
test -r /etc/systemd/user/t3code.service.d/overrides.conf
test ! -e /etc/systemd/user/t3code.service
systemctl --user daemon-reload
t3 service install --base-dir /home/codex/.t3
t3 service status
systemctl --user is-enabled t3code.service
systemctl --user is-active t3code.service
systemctl --user show t3code.service --property=DropInPaths --property=UMask
type -a t3
curl -fsS http://127.0.0.1:3773/.well-known/t3/environment | jq '{environmentId,label}'
```

Проверить единственную команду `~/.local/bin/t3`, прежний environmentId/label,
доступ с клиента, существующие треды и Codex login. Не печатать pairing tokens,
credentials, полное runtime state или содержимое userdata. Затем проверить
update UI: должна быть доступна возможность обновить remote server.

## Обновление

В user shell с доступным user manager:

```shell
t3 update --channel nightly
```

CLI запрашивает согласие на перезапуск. Для намеренного запуска из скрипта
требуется `--yes`. Remote update UI использует native launcher и сам выполняет
handoff. Ежедневного таймера нет: перезапуск во время работы запускает только
пользователь. Codex CLI остается отдельной npm-установкой в `~/.local`.

Remote self-update переключает runtime через launcher. Symlink команды может
остаться на прежней версии до следующего CLI `t3 update --channel nightly`:
CLI updater отдельно обновляет symlink и native unit. Каталоги старых версий -
rollback assets, а не параллельно работающие T3.

## Rollback handoff

Если native service не заработал, сначала остановить его из user shell:

```shell
systemctl --user disable --now t3code.service
exit
```

Сразу после этой выкладки, если других deployments еще не было, из host shell:

```shell
sudo -n nixos-rebuild switch --rollback
sudo -n nixos-container run codex -- systemctl start t3.service
sudo -n nixos-container run codex -- systemctl is-active t3.service
sudo -n nixos-container run codex -- runuser -u codex -- curl -fsS http://127.0.0.1:3773/.well-known/t3/environment | jq '{environmentId,label}'
```

Это откат всей предыдущей NixOS generation, включая остальные изменения той
выкладки. При последующих deployments выбрать сохраненную generation явно.
Не удалять `~/.t3` и не перезаписывать базу старой копией после успешных новых
записей. Symlink официального CLI остается в home; для аварийного старта
используется system unit с явным Nix store path.

## Проверка после handoff, 2026-10-21

`systemctl --user` подтвердил active/running native unit из home codex и Nix
drop-in в дереве user units. Endpoint сохранил environmentId/label и сообщает
`serverSelfUpdate=boot-service`, `serverSelfUpdateProgress=true`. CLI
`~/.local/bin/t3` имеет версию 0.1.1-nightly.20261020.3411, Codex 0.163.0
сохранил текущий ChatGPT login. Основной Nix system unit T3 удален.
