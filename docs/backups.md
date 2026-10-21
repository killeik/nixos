# Резервные копии oggy

`hosts/oggy/selfhost/backups.nix` подключается через модуль selfhost хоста oggy. Штатный таймер
`btrbk-oggy.timer` ежедневно запускает `btrbk-oggy.service`. Пропущенный запуск
догоняется после включения сервера.

Перед снимками root-процесс `ExecStartPre` через SQLite Backup API копирует
живые базы Forgejo и Grafana, включая committed WAL, и проверяет
`PRAGMA integrity_check` на копиях. Miniflux выгружается командой
`docker exec miniflux-db pg_dump -U miniflux -d miniflux -Fc`; затем
`docker exec -i miniflux-db pg_restore --list` проверяет чтение оглавления.
Это не полный тест восстановления PostgreSQL: его нужно периодически
восстанавливать в отдельную тестовую БД и проверять приложение.

Проверенные файлы лежат в `/var/lib/oggy-database-backups`:
`forgejo.sqlite`, `grafana.sqlite`, `miniflux.dump`. Каталог доступен только
root (`0700`), файлы создаются с `0600`. До проверки всех трех копий предыдущие
файлы не заменяются. Публикация каждого файла атомарна; весь набор из трех
файлов не является одной атомарной операцией. При ошибке подготовки или таймауте
30 минут btrbk не запускается, новые снимки не создаются и старые не удаляются.
Приложения при ежедневном запуске не останавливаются.

После подготовки штатный btrbk работает как `btrbk` с sudo backend и создает
read-only снимки в `/var/lib/btrbk/snapshots`:

- `root.<timestamp>`: `/`, являющийся Btrfs top-level subvolume ID 5;
- `codex.<timestamp>`: `/var/lib/nixos-containers/codex`.

`/var/lib/btrbk` и `snapshots` имеют режим `0750`, группа `btrbk`.
`StateDirectoryMode=0750` не дает systemd расширить права каталога при старте.
Снимки содержат секреты; доступ к учетной записи btrbk и ее sudo правам
равнозначен доступу к данным root. Пользователей в группу btrbk не добавлять.
Не публиковать каталог через HTTP, Samba или контейнерные bind mounts.

## Хранение

`snapshot_preserve_min = latest` всегда сохраняет самый свежий снимок.
`snapshot_preserve = 7d 4w 3m 0y` сохраняет первые дневные снимки за последние
7 календарных дней, первые дневные в неделе за 4 недели и первые недельные
в месяце за 3 месяца. Годовых точек нет. Это календарные интервалы btrbk,
а не строго 7 + 4 + 3 файлов: интервалы пересекаются и включают границу.
Неделя начинается в воскресенье по умолчанию, время локальное Europe/Moscow.

Несколько запусков за день не удерживают все внутридневные снимки: остаются
первый дневной и latest, остальные можно удалить при следующем успешном run.
Явный `timestamp_format = long` создает новое имя с часами и минутами;
повтор в ту же минуту получает суффикс `_N`, а не переиспользует старый снимок.
После появления latest следующего дня за предыдущий остается одна дневная точка.
Значение `all`, являющееся default для `snapshot_preserve_min`, намеренно
не используется. Семантика: [btrbk.conf(5)](https://digint.ch/btrbk/doc/btrbk.conf.5.html#_retention_policy).
Ручной `btrbk prune/run` обходит подготовку БД; обычный запуск делать только
через systemd service. Dry-run безопасен.

Legacy-наборы `/home/killeik/selfhost/backups/update-*` не импортируются
в новый каталог и этой политикой не удаляются. Их отдельное удаление выполняется
только после успешного первого набора root + codex и проверки дампов.

`nix.gc` запускается еженедельно с `--delete-older-than 30d`, stateVersion
не меняется. Снимки удерживают старые блоки Nix и Docker: GC/prune может
удалить пути из живой системы, не увеличив свободное место. Блоки освободятся,
только когда исчезнут все удерживающие их снимки. Новый root-снимок тоже
содержит текущие `/nix/store` и Docker state; снимок не является исключением
этих данных из хранения. Следить за `btrfs filesystem usage /`, особенно
metadata: retention не гарантирует фиксированный размер в гигабайтах.

## Проверка после подключения модуля

В репозитории:

```shell
git add -- hosts/oggy/selfhost/backups.nix scripts/backup-databases.py docs/backups.md
nix flake check
nix eval --json .#nixosConfigurations.oggy.config.systemd.services.btrbk-oggy.serviceConfig
nix eval --json .#nixosConfigurations.oggy.config.nix.gc
```

На oggy после согласованного deploy:

```shell
sudo -n systemctl start btrbk-oggy.service
sudo -n systemctl status btrbk-oggy.service --no-pager
sudo -n journalctl -u btrbk-oggy.service -n 60 --no-pager
sudo -n btrbk -c /etc/btrbk/oggy.conf --print-schedule dryrun
sudo -n btrfs subvolume list -r /var/lib/btrbk/snapshots
sudo -n stat -c '%a %U %G %n' /var/lib/btrbk /var/lib/btrbk/snapshots /var/lib/oggy-database-backups
systemctl list-timers btrbk-oggy.timer nix-gc.timer
```

Проверить оба имени снимков, свежие дампы внутри root-снимка и read-only flag
каждого снимка (`sudo -n btrfs property get <snapshot> ro`). При сбое создания
одного снимка btrbk не гарантирует атомарную пару root + codex: проверить оба
перед удалением legacy-наборов. Не удалять старые копии по одному лишь exit 0
предварительной подготовки.

## Восстановление

Это локальные копии на том же диске. Они помогают после ошибочного изменения
или удаления, но не защищают от потери диска, файловой системы или root-доступа
злоумышленника. Внешняя копия пока не настроена.

Btrfs snapshots не рекурсивны: root не содержит данные nested subvolumes,
codex снимается отдельно; nested `srv`, `var/lib/machines`, `var/lib/portables`,
`tmp`/`var/tmp` также не копируются рекурсивно. `/boot` является отдельной
файловой системой и в эти снимки не входит. Остальное состояние имеет
crash-consistent уровень, как после внезапного выключения. Дампы каждой БД
согласованы отдельно, но не являются общей транзакцией между БД, git-репозиториями
Forgejo и другими файлами; root и codex также создаются последовательно.

1. Выбрать проверенную пару снимков и отключить backup/GC timers на время
   восстановления. Сначала сохранить текущее поврежденное состояние отдельно,
   если оно еще может пригодиться. Полный root восстанавливать из rescue-системы;
   не заменять живой `/`. ID 5 нельзя переключить как обычный root-subvolume:
   восстановление требует копирования содержимого либо изменения схемы загрузки.
2. До запуска приложений восстановить нужные файлы и секреты: env-файлы
   `/home/killeik/selfhost`, Forgejo data/config, Grafana config и
   `/var/lib/grafana/secret_key`. Сохранять исходных владельцев и права.
   Для полного восстановления отдельно восстановить codex subvolume из выбранного
   codex-снимка, затем проверить загрузчик и `/boot`.
3. Остановить Forgejo/Grafana при замене их БД. Из выбранного root-снимка взять
   проверенные `var/lib/oggy-database-backups/*.sqlite`, заменить соответствующие
   рабочие БД, удалить устаревшие `-wal`/`-shm` только у остановленного приложения
   после сохранения текущего состояния. Восстановить владельца/права по рабочему
   каталогу, проверить `integrity_check` до запуска. Не смешивать новый дамп
   с более старыми секретами или данными без проверки совместимости.
4. Остановить Miniflux, запустить совместимый PostgreSQL (та же major либо
   поддерживаемый переход), создать пустую БД `miniflux` с владельцем `miniflux`
   и восстановить `miniflux.dump` через `pg_restore --exit-on-error -U miniflux
   -d miniflux`. Пароли брать из восстановленных env, в команды и логи не выводить.
   Raw PostgreSQL data из root-снимка не заменяет этот логический restore.
5. Запустить приложения, проверить вход, репозитории Forgejo, Grafana и Miniflux,
   затем включить timers. При восстановлении одной БД полный root откатывать
   не требуется.

## Проверка 2026-10-21

Первый набор root/codex создан, read-only флаги и права проверены. SQLite
проверены непосредственно из неизменяемого снимка через URI `mode=ro&immutable=1`:
WAL-mode SQLite может требовать создать shm при обычном read-only открытии.
Miniflux dump из снимка полностью восстановлен в отдельную временную БД;
счетчики 1 user, 153 feeds, 1879 entries совпали. Тестовая БД удалена.
Старые manual snapshots и standalone dumps очищены после этих проверок.

TODO: Добавить зашифрованное удаленное хранение копий. Назначение и recovery key
еще не выбраны; сейчас снимки на том же диске не защищают от его потери.
