# Sparky: Arch Linux / Omarchy

Это не NixOS target. Источник настроек node_exporter хранится здесь,
пакет и systemd unit принадлежат официальному репозиторию Arch `extra`.

Хост: `sparky`, интерфейс `enp7s0`, текущий DHCP IPv4 `192.168.1.171/24`.
Prometheus на oggy: `192.168.1.2`. Target использует `sparky.home.arpa:9100`: имя
проверено через DNS на oggy и сейчас указывает на `192.168.1.171`. DHCP может
менять адрес, сохраняя имя sparky в DNS роутера; reservation не требуется.
Exporter слушает IPv4 `0.0.0.0:9100`, поэтому смена DHCP адреса не ломает запуск.
UFW разрешает этот порт только с oggy; IPv6 listener отсутствует.

## Установка и применение

Из корня репозитория на sparky. Сначала проверить hostname, адрес oggy и
активный UFW (`sudo ufw status verbose`). Не применять при выключенном UFW.
Порядок правил важен: разрешение oggy должно стоять перед запретом 9100,
оба правила должны предшествовать существующим широким разрешениям.
Другие правила и политики UFW не изменять.

```sh
pacman -Si prometheus-node-exporter
omarchy pkg add prometheus-node-exporter
sudo install -o root -g root -m 0644 hosts/sparky/prometheus-node-exporter /etc/conf.d/prometheus-node-exporter
sudo ufw insert 1 deny in proto tcp from any to any port 9100 comment 'node exporter deny other sources'
sudo ufw insert 1 allow in proto tcp from 192.168.1.2 to any port 9100 comment 'node exporter oggy only'
sudo ufw status numbered
sudo systemctl enable prometheus-node-exporter.service
sudo systemctl restart prometheus-node-exporter.service
```

`omarchy pkg add` использует `pacman -S --needed`, не обновляет базы и систему.
Не делать отдельный `pacman -Sy`: это создает частичное обновление Arch.
Повторное применение тех же правил UFW пропускает существующие правила.
Настройки находятся в EnvironmentFile штатного unit; временные systemd overrides
не нужны. UFW и exporter должны оставаться enabled для обычной перезагрузки.

## Проверка

```sh
systemctl is-enabled ufw prometheus-node-exporter
systemctl is-active prometheus-node-exporter
curl --fail --silent http://127.0.0.1:9100/metrics -o /dev/null -w '%{http_code}\n'
ssh oggy.home.arpa 'curl --fail --silent --max-time 15 http://sparky.home.arpa:9100/metrics -o /dev/null -w "%{http_code}\n"'
```

С другого LAN хоста TCP 9100 должен быть недоступен.
Loopback доступен для локальной диагностики.
Для стандартного Node Exporter Full dashboard доступны CPU, memory, filesystem,
disk, network и load метрики. systemd collector включен явно; hwmon и thermal_zone
сохраняют defaults upstream. Фактический набор температур зависит от датчиков.

Основные метрики: `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`,
`node_filesystem_avail_bytes`, `node_disk_read_bytes_total`,
`node_network_receive_bytes_total`, `node_load1`, `node_uname_info`,
`node_systemd_unit_state`, `node_hwmon_temp_celsius`,
`node_thermal_zone_temp`, `node_scrape_collector_success`.

Проверено 2026-10-21: пакет `1.12.1-1`, UFW enabled/active, exporter
enabled/active от `node_exporter`, конфиг в репозитории и `/etc/conf.d/`
побайтово совпадает. Локально и с oggy HTTP 200 (полный ответ около 227 KB).
С OpenWrt `192.168.1.1` curl завершился timeout (exit 28, HTTP 000),
счетчик DROP правила 9100 вырос с 5 до 9 пакетов. Повторные команды UFW
пропустили существующие правила, порядок allow/deny сохранился.

Метрики содержат 96 CPU samples, 9 filesystem, 2 disk, 2 network,
1245 systemd unit states и 9 hwmon температур. Collectors `systemd`,
`hwmon`, `thermal_zone` возвращают success=1; thermal zones отсутствуют,
поэтому `node_thermal_zone_temp` не публикуется. Некоторые необязательные
default collectors (например, zfs, nfs, rapl) возвращают success=0;
не использовать общий alert на любой collector=0 без выбора нужных collectors.
Перезагрузка не выполнялась; автозапуск проверен по enabled unit и штатному
EnvironmentFile. Prometheus target и dashboards применяются отдельно на oggy.
