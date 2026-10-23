# Резервные копии oggy

На oggy:

```sh
# Создать дампы БД и снимки через штатный сервис
sudo systemctl start btrbk-oggy.service
sudo journalctl -u btrbk-oggy.service -n 60 --no-pager

# Проверить расписание, снимки и место
systemctl list-timers btrbk-oggy.timer nix-gc.timer
sudo btrbk -c /etc/btrbk/oggy.conf --print-schedule dryrun
sudo btrfs subvolume list -r /var/lib/btrbk/snapshots
sudo btrfs filesystem usage /
```

Настройки хранения: [backups.nix](../hosts/oggy/selfhost/backups.nix).
Подготовка дампов: [backup-databases.py](../scripts/backup-databases.py).
Не запускать `btrbk run/prune` напрямую: это обходит подготовку БД.
Снимки содержат секреты и лежат на том же диске; от потери диска они не защищают.

## Восстановление

1. Сохранить поврежденное состояние, остановить backup/GC timers и затронутые приложения.
2. Выбрать снимки `root.<timestamp>` и `codex.<timestamp>` в `/var/lib/btrbk/snapshots`.
   Root-снимок не включает вложенные subvolumes и `/boot`; codex восстанавливается отдельно.
   Полный root восстанавливать из rescue: `/` использует Btrfs top-level ID 5,
   его нельзя переключить как обычный root-subvolume.
3. Восстановить данные, секреты, владельцев и права из выбранного снимка.
   Дампы БД находятся внутри root-снимка в `var/lib/oggy-database-backups`.
   Копии разных БД и файлов не являются одной общей транзакцией.
4. SQLite: у остановленного приложения сохранить текущую БД и ее `-wal`/`-shm`,
   заменить БД проверенным дампом, убрать старые `-wal`/`-shm`, восстановить права
   и проверить `PRAGMA integrity_check` до запуска.
   Headscale восстанавливать вместе с ключами из `/var/lib/headscale`;
   Grafana - вместе с `/var/lib/grafana/secret_key`.
5. Miniflux: остановить приложение, создать пустую БД `miniflux` с владельцем `miniflux`
   в совместимом PostgreSQL и восстановить `miniflux.dump` через
   `pg_restore --exit-on-error -U miniflux -d miniflux`.
   Пароль брать из восстановленного env; raw PostgreSQL data не заменяет логический restore.
6. Запустить приложения, проверить вход и данные, включить timers.
   Для восстановления одной БД полный root откатывать не нужно.
