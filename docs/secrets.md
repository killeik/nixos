# Секреты oggy

`sops-nix` подключен, но `oggy.sops.enable` по умолчанию выключен. Этот PR
не меняет runtime-файлы и не требует ключей для eval/build. В Git пока нет
зашифрованных секретов или получателей. Включение - отдельная миграция.

Каждый существующий файл шифруется целиком (`binary`), без пересборки env,
нормализации переводов строк или генерации новых значений. sops-nix заменяет
runtime-файл symlink на файл в `/run/secrets`, доступный после расшифровки.
Имена runtime-путей и потребители остаются прежними. Корневые файлы имеют
`root:root`, `0600`; ключ Grafana - `grafana:grafana`, `0600`.

## Bootstrap и миграция

Выполнять отдельно в согласованное окно на oggy, без `set -x` и вывода
содержимого. Сначала сверить `stat` всех исходников с владельцами выше.
Если фактические права отличаются, остановиться и согласовать их до включения.
Сохранить все десять исходников с метаданными в закрытой резервной копии вне
Git, включая `/var/lib/grafana/secret_key`; проверить возможность восстановления.
Существующие logical backups не заменяют копию этих файлов.

1. Получить настоящий age recipient оператора восстановления и сохранить его
   private key офлайн. На oggy создать отдельный host key, если его еще нет:

   ```shell
   sudo install -d -m 0700 -o root -g root /var/lib/sops-nix
   sudo test ! -e /var/lib/sops-nix/key.txt
   sudo sh -c 'umask 077; age-keygen -o /var/lib/sops-nix/key.txt'
   sudo age-keygen -y /var/lib/sops-nix/key.txt
   ```

   Последняя команда выводит только публичный recipient. Private keys не
   добавлять в Git, Nix store, переписку или логи. Не использовать ключи-примеры.
   Сохранить host private key отдельно в защищенной резервной копии.

2. На защищенном checkout получить `sops` и `age` из pinned nixpkgs:
   `nix shell --inputs-from . nixpkgs#sops nixpkgs#age`. На oggy инструменты
   должны быть доступны и для команд через sudo (использовать полный путь).
   Шифрование можно выполнить прямо на oggy, чтобы plaintext не покидал хост.
   Указать оба настоящих публичных recipient через запятую:

   ```shell
   set -euo pipefail
   read -r -p 'Host and recovery age recipients, comma-separated: ' recipients
   sops_bin=$(command -v sops)
   umask 077
   mkdir -p hosts/oggy/secrets
   while read -r source name; do
     sudo test -s "$source" || exit 1
     sudo test ! -L "$source" || exit 1
     sudo "$sops_bin" --encrypt --age "$recipients" --input-type binary --output-type json \
       "$source" > "hosts/oggy/secrets/$name.sops" || exit 1
     sudo env SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt \
       "$sops_bin" --decrypt --input-type json --output-type binary \
       "hosts/oggy/secrets/$name.sops" | sudo cmp --silent "$source" - || exit 1
   done <<'FILES'
   /home/killeik/selfhost/caddy.env caddy.env
   /home/killeik/selfhost/miniflux.env miniflux.env
   /home/killeik/selfhost/postgres.env postgres.env
   /home/killeik/selfhost/silverbullet.env silverbullet.env
   /home/killeik/selfhost/excalidash/backend.env backend.env
   /var/lib/qingping/mqtt-password mqtt-password
   /var/lib/qingping/metrics-password metrics-password
   /var/lib/qingping/telegram.env telegram.env
   /var/lib/qingping/link-token link-token
   /var/lib/grafana/secret_key secret_key
   FILES
   ```

   Использовать shell с `set -euo pipefail`. Ошибка любой команды прерывает
   миграцию. Проверить расшифровку и с recovery key на защищенной машине,
   сравнивая байты без вывода. В Git переносятся только десять ciphertext-файлов.

3. Добавить `oggy.sops.enable = true;` в `hosts/oggy/default.nix`.
   Проверить diff, явно добавить ciphertext и исходники в Git, выполнить
   `nix fmt -- --ci`, `nix flake check`, `nix build .#nixosConfigurations.oggy.config.system.build.toplevel`.
   Сборка проверяет структуру ciphertext, но не наличие/пригодность host key.
   Перед switch повторить проверку расшифровки именно host key на oggy.

4. После согласованного switch сравнить каждый runtime-файл с исходной копией
   через `cmp --silent`, проверить `stat -L`, symlink и состояние потребителей.
   Каталог `/var/lib/qingping` должен остаться `root:root`, `0700`.
   Для первого перехода запланировать проверку/перезапуск потребителей:
   установщик может считать создание секрета изменением.

`restartUnits` перезапускает только потребителей измененного plaintext:
Caddy, Miniflux, PostgreSQL, SilverBullet, Excalidash backend; MQTT-пароль -
Mosquitto и qingping-reporting; metrics-пароль - Mosquitto и qingping-exporter;
Telegram env и ключ Grafana - Grafana. `link-token` не перезапускает службы.
Существующие restart triggers Caddy и таймер reporting сохранены.

Не менять значения при миграции. `DATABASE_URL` Miniflux должен соответствовать
существующему паролю роли в БД; смена `POSTGRES_PASSWORD` не меняет пароль уже
инициализированной БД. Ротация требует отдельного плана и согласованного SQL.
Не генерировать заново `API_KEY_HASH_PEPPER` или Grafana `secret_key`: это
ломает существующие API keys или расшифровку сохраненных учетных данных.
При включенном sops автоматическая генерация этих двух значений отключена.

## Восстановление

На новом хосте сначала восстановить каталоги с исходными правами, host age
key (`root:root`, `0600`, родитель `0700`) и данные сервисов, затем активировать
поколение с ciphertext. Имена пользователей и владельцы должны совпадать.
Recovery key позволяет расшифровать файлы и переупаковать их для нового host
recipient. Для смены recipients переупаковать все десять файлов, проверить
обоими ключами, затем удалить старый recipient. Потеря обоих private keys
означает невозможность восстановления из ciphertext.

Откат поколения возвращает старые ciphertext, но не откатывает пароль БД,
внешние токены или данные приложений. Отключение `oggy.sops.enable` само по
себе не возвращает обычные файлы: symlink в `/run` не переживет reboot.
Для отказа от sops в согласованное окно остановить потребителей, восстановить
исходные файлы из закрытой копии с заменой symlink (не писать сквозь него),
исходными владельцами/правами и проверкой байтов; затем активировать конфиг
с выключенным sops и запустить/проверить потребителей. До завершения этой
проверки не удалять резервную копию, ключи или старые Nix generations.
