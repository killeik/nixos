# oggy: варианты обслуживания после аудита

Материал для выбора, проверено 2026-10-20 по audit.md, файлам checkout и
read-only SSH. Нумерация соответствует аудиту. Изменения ниже не внесены
в Nix. Выбранные изменения backups, T3 и formatter применены и проверены 2026-10-21.
Ниже обсуждаются оставшиеся варианты; они автоматически не применялись.
Секретные значения не читались. Paths и права проверялись без содержимого.

Для проверки возможностей NixOS использован именно revision из flake.lock:
`09063bd1f2b36fd9fd793c36dfade7bd40a93dfc` (`nixos-unstable`).
API проверены по исходникам этого revision. Интеграционные `nix flake check`,
сборка системы и проверка на oggy прошли перед выкладкой.

## 13. tmpfiles вместо activation

Текущий activation script уже понятен и идемпотентен для обычных каталогов.
Проблемы, которую обязательно лечит tmpfiles, не найдено. Выгода перехода:
видно полный список path/mode/owner, меньше повторений `install -d`, стандартный
механизм создания каталогов при загрузке. Название tmpfiles не означает
временные данные: постоянные каталоги поддерживаются. Правило `d` с age `-`
не задает очистку по возрасту. Источники:
[systemd tmpfiles.d](https://www.freedesktop.org/software/systemd/man/latest/tmpfiles.d.html),
[модуль закрепленного NixOS](https://github.com/NixOS/nixpkgs/blob/09063bd1f2b36fd9fd793c36dfade7bd40a93dfc/nixos/modules/system/boot/systemd/tmpfiles.nix).

Пример узкой замены только двух строк:

```nix
systemd.tmpfiles.rules = [
  "d /home/killeik/selfhost/downloads 0755 killeik users -"
  "d /home/killeik/selfhost/miniflux-postgres 0700 999 999 -"
];
```

Это не заменяет генерацию случайного `excalidash/backend.env`. Soularr config
создается один раз и затем редактируется приложением; Caddyfile, наоборот,
обновляется из Git при каждом activation. Их нельзя превратить в одинаковое
правило копирования. Пустой SQLite-файл LaraPaper требует отдельной проверки
семантики создания/прав. Рекурсивный chown всех данных не нужен.

Выбор: оставить activation целиком; либо перенести только обычные каталоги,
оставив bootstrap в activation. Второй вариант немного короче, но некоторое
время придется читать два механизма. Не делать этот рефакторинг только ради
самого использования tmpfiles. Если выбирать его, проверить обычный switch,
холодную загрузку и владельцев до старта контейнеров.

## 14. Числовые UID/GID и комментарии

Ошибка прав не подтверждена. Числа здесь являются частью контракта mount с
образом, а не случайными NixOS users: PostgreSQL `999:999`, LaraPaper `82:82`,
Excalidash `1001:1001`; Forgejo явно получает `USER_UID/GID=1001`.
`1000:100` используется через PUID/PGID или `user` у нескольких контейнеров.
Не следует создавать на хосте пользователей с именами каждого приложения
только ради замены чисел: это дополнительная сущность без текущей выгоды.

Короткие комментарии полезны рядом с первыми тремя владельцами: какой образ
и какой его пользователь требуют эти права. Комментарий `999 is postgres`
без привязки к образу быстро устареет при смене variant/tag. Перед написанием
такого комментария проверить UID в точном действующем image через getent/id,
а не доверять общей таблице из интернета. В этом исследовании image users
повторно не проверялись; новых гарантий соответствия чисел нет.

Отдельно проверить `users.users.killeik.uid`: сейчас Nix явно его не задает,
а контейнерные PUID используют 1000. Это важно при чистом восстановлении на
новый хост; это повод проверить/зафиксировать существующий UID отдельно,
но не менять владельцев сейчас. Выбор: оставить; добавить 3 объясняющих
комментария после проверки образов. Общий UID framework не нужен.

## 15. Что нужно для восстановления кроме Git

Git восстанавливает flake, systemd/OCI declarations, Caddyfile, dashboard JSON
и начальный Soularr template. Он не восстанавливает пользователей приложений,
их БД, пароли, ключи, измененные через UI настройки и пользовательские файлы.
Переносить все UI-настройки в Nix не обязательно. Достаточно ясно провести
эту границу и иметь проверяемые копии state.

Конкретный минимальный inventory (пути на oggy):

| Данные | Что сохранять | Почему Git недостаточно |
| --- | --- | --- |
| Miniflux | `/home/killeik/selfhost/miniflux-postgres`, логический dump БД miniflux, `miniflux.env`, `postgres.env` | feeds, entries, пользователь и пароль БД |
| Forgejo | весь `/home/killeik/selfhost/forgejo`, включая `gitea/gitea.db` | БД, repositories, app.ini, ключи и вложения; одного dump SQLite мало |
| Grafana | `/var/lib/grafana`, включая `grafana.db` и `secret_key` | users и изменяемые настройки; ключ связан с зашифрованными секретами БД |
| Qingping | `/var/lib/qingping/{mqtt-password,metrics-password,link-token,telegram.env}` | MQTT, BLE pairing, Telegram |
| SilverBullet | `/home/killeik/selfhost/silverbullet/space`, `silverbullet.env` | заметки и доступ |
| Excalidash | `/home/killeik/selfhost/excalidash/{prisma,backups,backend.env}` | SQLite и постоянный pepper, который нельзя заменить случайным при restore |
| Syncthing | `/home/killeik/selfhost/syncthing` | identity устройства и settings; отдельно понимать, где оригиналы синхронизируемых файлов |
| Music stack | `/home/killeik/selfhost/{lidarr/config,prowlarr/config,qbittorrent/config,navidrome/data,slskd,soularr}` | БД, API keys, credentials и рабочий `soularr/config.ini` |
| Пользовательские файлы | `/home/killeik/selfhost/{music,downloads,larapaper/database,larapaper/generated-images}` | библиотека, загрузки, LaraPaper DB/изображения; при нехватке места downloads можно исключить только осознанно |
| Caddy | `caddy.env`, volumes `caddy_data` и `caddy_config` | Cloudflare token, сертификаты/ACME и runtime state; Caddyfile есть в Git |
| T3/Codex | весь `/var/lib/nixos-containers/codex`, особенно `/home/codex/{.t3,.codex,.local,.npmrc}` внутри него | userdata/auth/sessions, CLI/runtime, user unit и пользовательские настройки |
| Prometheus | `/var/lib/prometheus2`, если нужна история метрик | TSDB не в Git; без нее новый мониторинг работает с пустой историей |
| Идентичность хоста | `/etc/ssh/ssh_host_*`, нужные NetworkManager profiles из `/etc/NetworkManager/system-connections` | новые host keys меняют trust, сетевые профили не описаны полностью в Nix |

Важно: `.npmrc`, app.ini, Syncthing config и state каталогов могут содержать
секреты. Inventory - список путей, а не разрешение печатать файлы или класть
их в Git. На сервере подтверждены активные mounts Caddy в
`/var/lib/docker/volumes/{caddy_data,caddy_config}/_data`; старые volumes
`selfhost_caddy_*` не используются Caddy и не являются его текущей копией.
У FlareSolverr обнаружен anonymous volume `/config`: назначение его содержимого
не установлено, не объявлять его безусловно ненужным и не смешивать с
критичными данными без проверки. Содержимое volumes не читалось.

До очистки существовали `/home/killeik/selfhost/backups/update-2026-10-20/{root,codex}`,
`miniflux.dump`, `forgejo.db`, `grafana.db`; это локальные точки перед
обновлением. Само наличие файла не доказывает полный restore. Теперь настроены
ежедневные snapshots и согласованные копии основных БД: см.
[backups.md](backups.md). Пути `/var/lib/btrbk/snapshots` и `/var/lib/oggy-database-backups` проверены.
Legacy-наборы удалены после проверки нового снимка и тестового восстановления PostgreSQL.

Для PostgreSQL нужен проверенный pg_dump/pg_restore, для живого SQLite -
Backup API или остановленное приложение, а не произвольный cp одного .db.
Источники: [PostgreSQL SQL dump](https://www.postgresql.org/docs/18/backup-dump.html),
[SQLite Backup API](https://www.sqlite.org/backup.html).
Grafana использует secret_key для защиты секретов в БД:
[Grafana configuration](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#secret_key).

Хранилище копий - отдельный выбор. Snapshot на том же диске помогает от
ошибочного удаления, но не от потери диска; snapshots не включают вложенные
subvolumes рекурсивно, поэтому codex сохраняется отдельно.
[Btrfs subvolume manual](https://btrfs.readthedocs.io/en/latest/btrfs-subvolume.html).
Практичный следующий шаг - зашифрованная копия критичного state на другой
физический носитель/хост. Адрес назначения, доступный объем и допустимая
потеря последних данных еще не выбраны. Не придумывать удаленный target.

Restore-проверка: на пустом изолированном окружении поднять Git-конфиг,
вернуть state/secret files с исходными numeric owners, восстановить БД,
проверить вход, Forgejo repositories, feeds Miniflux и T3 threads/auth.
Восстанавливать БД совместимыми версиями; SSH identity и секреты вернуть
до подключения клиентов. Локальный backup и внешний backup - независимые
выборы, Git не заменяет ни один из них.

## 16. Границы модулей: конкретный минимальный вариант

Сейчас MQTT broker/users/1883 находятся в configuration.nix, а потребители,
device topic, reporting и alerts - в qingping.nix. Самая маленькая полезная
перестановка: перенести Mosquitto с его firewall 1883 в qingping.nix, а
Grafana proxy port 3000 и его firewall из qingping.nix в monitoring.nix.
Exporter scrape, dashboard и Qingping alerts оставить в qingping.nix:
они описывают одну функцию устройства, хотя расширяют monitoring options.
Пакет exporter можно пока оставить там же. Не нужна отдельная папка на
каждый сервис и не нужен options API для одного хоста.

Предлагаемое дерево после этого выбора:

```text
flake.nix                      # targets, inputs, formatter
configuration.nix              # imports, host users/network/SSH/boot
hardware-configuration.nix     # конкретный диск и железо
selfhost.nix                   # Docker stack, network, mounts, Slskd guard
selfhost/caddy/Caddyfile        # все HTTP routes
monitoring.nix                 # Grafana, Prometheus, node exporter, proxy 3000
qingping.nix                   # Mosquitto, exporter, reporting, dashboard, alerts
codex.nix                      # nspawn, T3 runtime integration, egress
backups.nix                    # snapshots/DB backup/retention (работа parent)
selfhost-remote.nix            # будущая VM отдельно от oggy
dashboards/qingping.json
docs/
```

Выбор: оставить дерево; сделать эти два переноса. У второго есть небольшой
выигрыш в навигации. Дробить selfhost.nix на 17 файлов только из-за длины
нет оснований. Проверка переносов - одинаковая вычисленная конфигурация,
а не только успешный parser.

## 17. Закрепить текущий datasource UID

Это узкая осмысленная правка: в объект Prometheus в monitoring.nix добавить
`uid = "PBFA97CFB590B2093";`. Именно этот UID уже используют alert rules
в qingping.nix; существование UID подтверждено исходным аудитом, здесь
API Grafana с credentials повторно не запрашивался. Перед deploy сверить
текущий UID без вывода секретов.

Без явного uid Grafana генерирует его. Заданный UID является стабильной
ссылкой из других конфигураций. Это не исправление уже сломанных alerts,
а устранение неявного контракта при пересоздании datasource/restore.
Сохранение существующего значения не требует миграции ссылок.
[Grafana datasource provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/#data-sources).

Не переименовывать UID в красивое `prometheus` отдельно: тогда придется
одновременно менять ссылки dashboard/alerts и проверять существующий state.
Выбор: оставить неявную связь; явно закрепить существующий UID. Второе
предпочтительно по соотношению размера изменения и понятности.

## 18. Grafana socket или TCP

Настоящая сложность socket здесь - граница native service и Docker:
bind mount `/run/grafana`, Unix permissions `0660`, after Grafana у Caddy,
`RuntimeDirectoryPreserve=yes`. Последнее сохраняет каталог при остановке,
что нужно для bind mount: удаление и пересоздание host directory оставляет
контейнер на старом inode. Это не повод удалять preserve как лишнюю настройку.
[systemd RuntimeDirectoryPreserve](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#RuntimeDirectoryPreserve=).

TCP уберет mount, socket permissions и эту зависимость от inode. Но
`127.0.0.1` Caddy - loopback самого Docker-контейнера, не native Grafana.
Нужно выбрать достижимый адрес хоста, bind Grafana и firewall. Например,
Grafana на отдельном TCP-порту, доступном с selfhost bridge, Caddy проксирует
на gateway `172.19.0.1`; сейчас этот gateway подтвержден network inspect.
Не использовать 3000 одновременно как host Grafana bind и Caddy published
port `192.168.1.2:3000:3000`: получится конфликт адресов при wildcard bind.
Вариант с отдельным 3001 потребует ограничить host INPUT с Docker bridge и
проверить недоступность из LAN. Это план миграции, не готовая конфигурация.
[Docker bridge networking](https://docs.docker.com/engine/network/drivers/bridge/).

Еще вариант - native Caddy: socket остается между двумя host services,
исчезает Docker mount, но нужно заменить Cloudflare-enabled image на
совместимую native сборку с DNS module и мигрировать Caddy data.
Перевод только ради одного socket больше текущей задачи.

Выбор сейчас: сохранить уже работающий socket. TCP имеет смысл, если
появляются повторные реальные сбои mount/permissions или принимается общее
решение о host endpoints. Тогда проверить рестарты Grafana и Caddy в обоих
порядках, reboot, HTTPS route и текущий LAN endpoint 3000.

## 19. Docker network: что реально есть в текущем NixOS

Есть native OCI option `containers.<name>.networks = [ "selfhost" ];`.
Он превращается в `--network=selfhost`; создание сети в модуле отсутствует.
`dependsOn` описывает зависимости только от других OCI containers.
Проверены [oci-containers.nix](https://github.com/NixOS/nixpkgs/blob/09063bd1f2b36fd9fd793c36dfade7bd40a93dfc/nixos/modules/virtualisation/oci-containers.nix)
и [docker.nix](https://github.com/NixOS/nixpkgs/blob/09063bd1f2b36fd9fd793c36dfade7bd40a93dfc/nixos/modules/virtualisation/docker.nix)
точного lock revision. Native `virtualisation.oci-containers.networks` или
`virtualisation.docker.networks` для декларации создания Docker network в
этих модулях нет. Нельзя предлагать такой выдуманный option.

| Вариант | Что исчезает | Цена для oggy |
| --- | --- | --- |
| Оставить NixOS OCI + oneshot | Ничего; сеть уже создается декларативной unit | Самый маленький вариант, все остается systemd/Nix |
| OCI `networks` вместо extraOptions | Одна сырая CLI option | Косметика; oneshot и dependencies остаются |
| Docker Compose | Compose сам создает network через `networks`/`ipam` | Перенос 17 containers и управление их lifecycle, env/mounts, интеграция systemd и Slskd guard |
| Native NixOS services | Docker network не нужна мигрированным приложениям | Отдельная миграция каждого сервиса, state paths/users, версии, proxy endpoints; не все приложения имеют нужный модуль/версию |

Compose действительно владеет объявленными сетями, но `external: true`
снова требует уже существующую сеть. Источник:
[Compose networks](https://docs.docker.com/reference/compose-file/networks/).
Native services полезны, если нужны native lifecycle, packages и host
permissions сами по себе. Перенос Grafana/Prometheus уже показывает этот
подход; переносить весь stack для удаления 15 строк oneshot невыгодно.

У текущего oneshot есть две реальные границы: `inspect || create` не сверяет
subnet существующей сети, а прямой Requires/After на network есть не у всех
ее потребителей (Caddy и Slskd получают его явно/через guard). Гонка не
воспроизведена, но при пустом Docker state порядок запуска не гарантирован
всеми declarations. Узкая будущая правка - дать каждому selfhost container
Requires/After на тот же oneshot, без новых менеджеров. Не удалять и не
пересоздавать live network при несовпадении subnet: это отключит stack.

Выбор: оставить oneshot; при желании отдельным diff исправить зависимости.
Проверка на пустой сети и reboot нужна в изолированном окружении, без удаления
рабочей сети oggy. Compose и native migration - отдельные задачи.

## 20. Firewall: маленькая очистка или смена backend

На oggy проверены Docker 29.8.2 и `iptables v1.8.13 (nf_tables)`.
Суффикс nf_tables означает совместимый iptables frontend, а не автоматически
native nftables backend Docker. Текущие правила используют CODEX-EGRESS,
INPUT/FORWARD и Docker `DOCKER-USER` для Slskd; это действующие политики,
а не неиспользуемые остатки.

| Вариант | Выигрыш | Что придется проверить/поменять |
| --- | --- | --- |
| Оставить iptables, сузить подавление ошибок | Меньший diff, остается привычная интеграция DOCKER-USER | Отдельно проверять отсутствие цепочки/правила; ошибки добавления правил не скрывать |
| NixOS nft firewall + Docker iptables backend | NixOS INPUT/forward policy описывается nft rules | Два взаимодействующих набора правил и порядок hook; текущий shell переписать, риск конфликта forward policy |
| NixOS и Docker native nftables | Собственные таблицы описываются декларативно; меньше shell создания/очистки | Переписать обе политики, приоритеты hooks, NAT/forwarding и Slskd limits; DOCKER-USER отсутствует |

Native nftables backend появился в Docker 29 и на дату проверки обозначен
experimental. Он использует отдельные tables; user rules должны жить в своих
tables, а не править таблицы Docker. Accept в одной base chain не отменяет
drop в другой. Это больше, чем включить один bool.
[Docker nftables migration](https://docs.docker.com/engine/network/firewall-nftables/).
В текущем NixOS есть `networking.nftables.tables.<name>.{family,content}` и
`networking.firewall.extraInputRules/extraForwardRules`:
[nftables module](https://github.com/NixOS/nixpkgs/blob/09063bd1f2b36fd9fd793c36dfade7bd40a93dfc/nixos/modules/services/networking/nftables.nix),
[firewall nft module](https://github.com/NixOS/nixpkgs/blob/09063bd1f2b36fd9fd793c36dfade7bd40a93dfc/nixos/modules/services/networking/firewall-nftables.nix).

Не отключать Docker `iptables` в надежде, что NixOS allowedTCPPorts заменит
Docker NAT/isolation. Published ports проходят forwarding, и host INPUT
allowlist сама по себе не описывает весь их доступ.
[Docker packet filtering](https://docs.docker.com/engine/network/packet-filtering-firewalls/),
[DOCKER-USER](https://docs.docker.com/engine/network/firewall-iptables/).

Узкий первый вариант: ожидаемую ситуацию "цепочка уже существует" определять
отдельной проверкой, а создание/flush/append выполнять с видимыми ошибками.
Проверки `iptables -C ... || iptables -I ...` тоже различают отсутствие правила
и сбой не идеально; не заменять их на безусловное insert с дубликатами.
Stop cleanup может терпеть уже отсутствующие собственные объекты, но не
следует прятать stderr всех операций. Не загружать общий iptables-restore
с flush Docker tables.

Выбор: сохранить backend, отдельно улучшить диагностику. Native nftables -
отдельная миграция с консольным fallback: SSH доступ, codex DNS+internet,
запрет codex -> LAN/host, Caddy published ports, счетчики Slskd connlimit
и rate limit, Docker restart, firewall reload, reboot. nft syntax check
не доказывает сетевую изоляцию. Сейчас исправность не опровергнута, а
миграция ради сокращения shell может увеличить суммарную сложность.

## 21. Повторяющиеся константы: side-by-side материал

Ниже фрагменты текущих значений и вариант общей таблицы. Это иллюстрация
конкретного переноса, не новый custom options framework.

| Сейчас | Общая таблица |
| --- | --- |
| `configuration.nix`: listener address `192.168.1.2` | `oggy.lanAddress` |
| `qingping.nix`: MQTT URL и reporting `-h 192.168.1.2`, Caddy port bind | `oggy.lanAddress` |
| `codex.nix`: nameservers и два DNS allow rules `192.168.1.1` | `oggy.dnsAddress` |
| `codex.nix`: externalInterface `enp0s20f0u3u4` | `oggy.externalInterface` |
| `qingping.nix` и Mosquitto ACL: `ccb5d1327498` | `oggy.qingpingDeviceId` |
| `selfhost.nix`: network subnet и уже существующий slskdContainerIp let | `oggy.dockerSubnet`, `oggy.slskdAddress` |

Текущий код, сокращенный без изменения значений:

```nix
# configuration.nix
address = "192.168.1.2";
acl = [ "readwrite qingping/ccb5d1327498/#" ];
# qingping.nix
server = "tcp://192.168.1.2:1883";
topic_path = "qingping/ccb5d1327498/up";
# codex.nix
networking.nameservers = [ "192.168.1.1" ];
networking.nat.externalInterface = "enp0s20f0u3u4";
```

Вариант `oggy-values.nix`, обычный attrset:

```nix
{
  lanAddress = "192.168.1.2";
  dnsAddress = "192.168.1.1";
  externalInterface = "enp0s20f0u3u4";
  dockerSubnet = "172.19.0.0/16";
  slskdAddress = "172.19.255.254";
  qingpingDeviceId = "ccb5d1327498";
}
```

Потребитель, без specialArgs, mkOption и дополнительных слоев:

```nix
{ ... }:
let
  oggy = import ./oggy-values.nix;
in {
  services.mosquitto.listeners = [{
    address = oggy.lanAddress;
    users.qingping.acl = [ "readwrite qingping/${oggy.qingpingDeviceId}/#" ];
    # passwordFile остается существующим runtime path.
  }];
}
```

Каждый нужный модуль может импортировать тот же файл в своем let; во
вложенном `containers.codex.config` значение доступно через lexical scope.
Если все повторы после пункта 16 окажутся в одном файле, проще один местный
let, без нового файла. `slskdContainerIp` уже вынесен в let - он не проблема.
Interface, который встречается один раз, сам по себе выноса не требует.
Формат MAC в OpenWrt (`cc:b5:...`) отличается от MQTT ID; не добавлять
преобразователь только ради этой пары.

Ограничение: Caddyfile - статический файл с `10.231.40.2:3773`; импорт Nix
не изменит его. Сделать его шаблоном возможно, но это еще одна миграция.
Не обещать единый источник всех network values, оставив этот literal.
Выбор: оставить literals; объединить только реально повторяющиеся значения
местными let; либо одна таблица выше для нескольких файлов. Практическая
выгода появляется при смене LAN/DNS/устройства, а не от числа constants.

## 22. Секреты: inventory или sops-nix + age

Текущие механизмы выполняют разные задачи: env нужен приложениям,
LoadCredential дает файл сервису, Grafana secret_key читает сама Grafana.
Новый storage manager не обязан и не сможет сделать интерфейсы потребителей
одинаковыми. Не помещать значения в Nix strings/store.

Полный короткий inventory текущих явно объявленных файлов:

| Runtime file | Consumer | Restore requirement |
| --- | --- | --- |
| `/home/killeik/selfhost/caddy.env` | Docker Caddy | Cloudflare token |
| `/home/killeik/selfhost/miniflux.env` | Docker Miniflux | DATABASE_URL + YOUTUBE_API_KEY |
| `/home/killeik/selfhost/postgres.env` | Docker PostgreSQL | POSTGRES_PASSWORD согласован с DATABASE_URL |
| `/home/killeik/selfhost/silverbullet.env` | Docker SilverBullet | SB_USER |
| `/home/killeik/selfhost/excalidash/backend.env` | Docker Excalidash | сохранить существующий API_KEY_HASH_PEPPER |
| `/var/lib/qingping/mqtt-password` | Mosquitto + reporting credential | один согласованный пароль |
| `/var/lib/qingping/metrics-password` | Mosquitto + exporter credential | отдельный read-only MQTT user |
| `/var/lib/qingping/link-token` | повторная BLE настройка | сохранить вне Git |
| `/var/lib/qingping/telegram.env` | Grafana EnvironmentFile | token и chat ID |
| `/var/lib/grafana/secret_key` | Grafana file provider | восстановить вместе с DB, не генерировать новый без миграции |

Пять env-файлов selfhost проверены как root:root 0600, четыре Qingping files
как root:root 0600, Grafana key как grafana:grafana 0600. Это не полный
перечень секретов внутри application state: app.ini, Slskd/Soularr configs,
T3/Codex auth и прочее сохраняются вместе с каталогами из пункта 15.
Старый общий `.env` удален после проверки действующих declarations.
Рабочие env-файлы сохранены.

Вариант A: сохранить файлы как есть, поддерживать этот inventory и проверенную
зашифрованную внешнюю копию. Восстановление требует отдельно доставить файлы
до старта сервисов, согласовать пары DB password/URL и вернуть права. Для
одного хоста это самый короткий operational path, если копия действительно есть.

Вариант B: sops-nix хранит зашифрованный документ в Git, расшифровывает на
хосте при activation, управляет paths/owner/mode и restartUnits. Age key
или host SSH key должен уже быть доступен; незашифрованные данные не
нужно включать в store. Поддерживаются dotenv и binary: можно сохранить
нынешние env как цельные файлы вместо создания templating framework.
[sops-nix README](https://github.com/Mic92/sops-nix).

Цена B: еще один flake input, `.sops.yaml`/recipients, начальный перенос,
резервирование private age recovery key вне oggy, процедура добавления
replacement host и ротации. Новый ключ не расшифрует старый ciphertext;
потеря единственного decrypt key при потере сервера означает потерю секретов.
Изменение файла также не заменяет пароль внутри уже инициализированной
PostgreSQL DB - нужна отдельная согласованная ротация приложения и БД.
Backup пользовательского state sops не заменяет.

Выбор: сначала inventory + копия без смены механизма; sops-nix оправдан,
если хочется хранить восстановимый encrypted config рядом с Git и готов
обслуживать recovery key. Возвращаться к нему при нескольких хостах,
частых ручных доставках secrets или регулярных пропусках файлов при restore.
Не называть текущие runtime files ошибкой только из-за отсутствия sops.

## 24. Pins и изменение T3 runtime

Зафиксированный revision/hash обеспечивает воспроизводимый исходник и
защиту от неожиданной подмены. Проблема возникает, когда процедура
обновления считает `nix flake update` полным обновлением, а отдельный pin
забывает; когда нужен security/compatibility fix или перестает собираться
старый источник. Сам возраст pin не доказывает необходимость переписывать
пакет. mqtt2prometheus здесь небольшой рабочий Go exporter, менять его
только ради даты не нужно.

Его текущие pin points в qingping.nix: rev
`c324374c71ae1102c450d310e8efbbe8db9cbcb5`, source hash, vendorHash.
Обновлять их отдельным осмысленным шагом: upstream diff, build, прежние
metric names и MQTT password-file mode. Изменение vendorHash требуется
только при изменении vendored dependencies. Источник проекта:
[mqtt2prometheus](https://github.com/hikhvar/mqtt2prometheus).

Первоначальный audit описывал Nix-пакет T3 SEA и pin patchelf 0.15.2.
Теперь используется другой путь: официальный runtime в user home, native
user service, Nix отвечает за nix-ld/зависимости/drop-in/linger. В checkout
`t3code-nightly.nix` удаляется. Поэтому предлагать автоматизацию обновления
его version/hash или сохранение patchelf override теперь неактуально.
См. точные исходники installer/update и границу live-проверки в
[t3-runtime.md](t3-runtime.md). Handoff выполнен: работает native user service, endpoint сообщает
`serverSelfUpdate=boot-service`; ID окружения и Codex login сохранены.

Компромисс нового пути: T3 может обновляться штатным updater без Nix rebuild,
но `nixos-rebuild --rollback` больше не выбирает runtime из home. Нужны
backup userdata и понимание managed launcher rollback. Nix фиксирует систему,
официальный updater - T3; текущую runtime version учитывать отдельно.
Node SEA содержит runtime и application payload внутри executable:
[Node SEA](https://nodejs.org/api/single-executable-applications.html).
Не patch-ить его новым patchelf без проверки payload/startup. При официальной
установке этот custom patching path исчезает, его поддерживать незачем.

Выбор: сохранить custom pin только для mqtt2prometheus; проверять upstream
при плановом обслуживании и менять при полезном изменении. T3 runtime
вести по отдельной документированной процедуре, не создавать
второй updater timer.

## 25. selfhost-remote: задокументировать назначение позже

Target содержит disk `/dev/sda`, interface `ens3`, QEMU profile, SSH и disko.
Это не идентичная удаленная копия oggy stack: selfhost.nix/monitoring.nix
туда сейчас не импортированы. Успешная evaluation означает корректность
конфигурации, не пригодность к установке на произвольный VPS и не наличие
рабочего сервера.

Выбор сейчас: сохранить без расширения и пометить как заготовку будущего
target. Позже, когда будет конкретная машина, документировать ее назначение,
disk/interface, способ установки, owner доступа и нужные state/secrets.
Не запускать disko по шаблонному device и не удалять target только из-за
отсутствия текущего применения. Отдельная документация не требует сейчас
создавать универсальный multi-host module layer.

## 26. Formatter

Уже добавлен `formatter.x86_64-linux = ...nixfmt-tree` и команды в README.
Этот пункт не требует еще одного formatter или framework. Проверка:
`nix fmt -- --ci`; применять массовый format-only diff отдельным
понятным изменением либо только к реально изменяемым файлам. Косметика
description/generated hardware comment не является эксплуатационным fix.

## Короткий набор независимых решений для страницы выбора

- 13: оставить activation / перенести только каталоги в tmpfiles.
- 14: оставить числа / добавить проверенные image-specific комментарии.
- 15: принять inventory; отдельно выбрать внешний носитель и объем копии.
- 16: оставить границы / сделать только два конкретных переноса.
- 17: закрепить существующий datasource UID одной строкой.
- 18: оставить socket / отдельная TCP-миграция с bind/firewall тестом.
- 19: оставить oneshot; отдельно исправить зависимости всех потребителей.
- 20: оставить iptables и улучшить диагностику / отдельная nft migration.
- 21: literals / местные let / один attrset с реальными constants.
- 22: inventory + внешняя encrypted copy / sops-nix с recovery key.
- 24: mqtt2prometheus pin обслуживать явно; T3 уже идет к штатному updater.
- 25: сохранить заготовку, документировать при появлении реального target.
- 26: formatter уже настроен.
