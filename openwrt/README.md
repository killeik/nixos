# OpenWrt

## Мониторинг

На Xiaomi AX3000T с OpenWrt 24.10.5 установлен официальный легкий
`prometheus-node-exporter-lua` и пакеты `-openwrt`, `-wifi`, `-wifi_stations`, версия
`2025.07.15-r1`. Go exporter на роутере не используется.

Endpoint: `http://192.168.1.1:9100/metrics`, источник Prometheus - oggy
`192.168.1.2`. Служба procd включена в автозапуск и слушает интерфейс `lan`
(сейчас только IPv4 `192.168.1.1`, без IPv6-адресов).

Повторная установка из корня репозитория:

```sh
tar -C openwrt -cf - setup-monitoring.sh filesystem.lua |
  ssh -F /dev/null -i ~/.ssh/amnezia -o BatchMode=yes root@192.168.1.1 \
    'mkdir -p /tmp/openwrt-monitoring && tar -C /tmp/openwrt-monitoring -xf - && sh /tmp/openwrt-monitoring/setup-monitoring.sh'
```

Скрипт обновляет индексы opkg, устанавливает только четыре пакета и их зависимости,
копирует дополнительный коллектор, сохраняет UCI и перезапускает только exporter.
Firewall применяется через reload, сеть не перезапускается.
Для файловых систем используется небольшой `filesystem.lua`: в базовом пакете
этого выпуска такого коллектора нет. Он читает `/proc/mounts` и `df -Pk`.
Метрики inode и disk I/O не реализованы; полного набора Go node_exporter нет.

У LAN политика input=ACCEPT. Поэтому оба правила глобальные, в начале UCI:

- `firewall.node_exporter_oggy`: ACCEPT TCP/9100 только с `192.168.1.2`
  через `br-lan` на `192.168.1.1`;
- `firewall.node_exporter_reject`: REJECT TCP/9100 со всех остальных источников,
  включая guest, WAN и IPv6.

Глобальный REJECT выполняется раньше правил зон. Поэтому нельзя переносить
allow в `src=lan`: тогда fw4 отклонит даже oggy до перехода в input_lan.
Остальные правила firewall скрипт не заменяет.

Проверено 2026-10-21: HTTP scrape с oggy успешен, все 15 коллекторов имеют
`node_scrape_collector_success=1`; соединение с sparky отклоняется, счетчик
REJECT растет. Реальный запрос из guest/WAN не выполнялся; проверены bind
и скомпилированная глобальная цепочка `inet fw4 input`.
После установки свободно 37.1 MiB overlay, до установки было 37.5 MiB.

Основные имена метрик:

- `node_openwrt_info` (значение 1, labels: board_name, id, model, release,
  revision, system, target), используется стандартным дашбордом OpenWrt 18153;
- `node_cpu_seconds_total`, `node_load1`, `node_load5`, `node_load15`;
- `node_memory_MemAvailable_bytes`, `node_memory_MemTotal_bytes`;
- `node_filesystem_size_bytes`, `node_filesystem_avail_bytes`,
  `node_filesystem_free_bytes` (labels: device, mountpoint, fstype);
- `node_network_receive_bytes_total`, `node_network_transmit_bytes_total`;
- `node_nf_conntrack_entries`, `node_nf_conntrack_entries_limit`
  (при проверке 1268 и 32768);
- `wifi_stations`, `wifi_network_quality`, `wifi_network_bitrate`,
  `wifi_network_noise_dbm`, `wifi_network_signal_dbm`;
- `wifi_station_signal_dbm`, `wifi_station_inactive_milliseconds`,
  `wifi_station_transmit_kilobits_per_second`,
  `wifi_station_receive_kilobits_per_second`,
  `wifi_station_transmit_packets_total`, `wifi_station_receive_packets_total`.

Wi-Fi-метрики реально присутствуют; количество доступных station-метрик зависит
от драйвера и подключенных клиентов. Station byte counters и expected throughput
при проверке отсутствовали. Метки содержат SSID/BSSID и MAC клиентов, поэтому
endpoint закрыт для остальных устройств.

Проверка с oggy и на роутере:

```sh
# На oggy:
curl --fail --max-time 15 http://192.168.1.1:9100/metrics
# На OpenWrt:
/etc/init.d/prometheus-node-exporter-lua enabled
ubus call service list '{"name":"prometheus-node-exporter-lua"}'
netstat -lntp | grep :9100
nft list chain inet fw4 input
```

Для отключения сначала остановить exporter, затем удалить только его правила:

```sh
/etc/init.d/prometheus-node-exporter-lua stop
/etc/init.d/prometheus-node-exporter-lua disable
uci delete firewall.node_exporter_oggy
uci delete firewall.node_exporter_reject
uci commit firewall
/etc/init.d/firewall reload
```

## Conntrack tuning for Soularr and Slskd

Soularr can request directory contents from many Soulseek peers in a short
period. Slskd turns those requests into direct TCP connection attempts. Peers
that do not answer leave `SYN_SENT` entries in the OpenWrt conntrack table, so
the router can exhaust its table even though Slskd has already timed out.

The protection is split between both hosts:

- oggy limits new TCP connections from the Slskd container in the
  nftables table `ip slskd-guard`;
- OpenWrt keeps a 32K table, expires unanswered SYN attempts after 30 seconds,
  and keeps `TIME_WAIT` entries for 60 seconds.

## OpenWrt

Install the tracked sysctl file as:

```sh
cp 90-conntrack-tuning.conf /etc/sysctl.d/90-conntrack-tuning.conf
chmod 0644 /etc/sysctl.d/90-conntrack-tuning.conf
sysctl -p /etc/sysctl.d/90-conntrack-tuning.conf
```

Verify:

```sh
cat /proc/sys/net/netfilter/nf_conntrack_count
cat /proc/sys/net/netfilter/nf_conntrack_max
cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_syn_sent
cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait
```

## oggy

The declarative guard in `hosts/oggy/selfhost/default.nix` applies only to the static Slskd
container address `172.19.255.254`:

- at most 8 new TCP connections per second, with an initial burst of 25;
- reject new attempts above 256 concurrent tracked TCP connections;
- leave established connections and transfer traffic untouched;
- manage the guard declaratively through the NixOS nftables service.

Verify:

```sh
systemctl is-active nftables.service docker-slskd.service
sudo nft list table ip slskd-guard
```

## Rollback

On oggy, revert the guard values in `hosts/oggy/selfhost/default.nix` to 25 connections per
second, burst 100, and connlimit 512, then deploy the previous NixOS
configuration.

On OpenWrt, keep the 32K capacity but restore the previous TCP timeouts by
leaving only the `nf_conntrack_max` line in the sysctl file and applying:

```sh
sysctl -w net.netfilter.nf_conntrack_max=32768
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_syn_sent=120
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=120
```

Do not flush the conntrack table during rollback because that interrupts
unrelated active connections.
