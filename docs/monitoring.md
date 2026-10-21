# Мониторинг домашних хостов

Prometheus и Grafana работают на oggy. Targets опрашиваются раз в 30 секунд:

| Host | Target | Exporter |
| --- | --- | --- |
| oggy | 127.0.0.1:9100, job=node | NixOS node_exporter, systemd collector |
| sparky | sparky.home.arpa:9100, job=node | Arch prometheus-node-exporter, systemd collector |
| openwrt | 192.168.1.1:9100, job=openwrt | prometheus-node-exporter-lua, Wi-Fi/OpenWrt и filesystem |

Label `host` дает понятное имя в уведомлениях. `instance` сохраняет host:port
для стандартных dashboards. Имя sparky.home.arpa проверено из oggy и обновляется
через DHCP/DNS роутера; статический адрес sparky не требуется.

На sparky UFW разрешает TCP 9100 только с oggy. OpenWrt слушает только LAN,
глобальные правила fw4 разрешают oggy и отклоняют остальные источники до
перехода в зоны. oggy exporter остается доступен только через loopback.
Установка и проверка: [sparky](../hosts/sparky/README.md),
[OpenWrt](../openwrt/README.md). Перезагрузка для установки не нужна.

## Dashboards

Провижининг хранится рядом с мониторингом, JSON - в hosts/oggy/selfhost/grafana/dashboards.
В Grafana folder Home доступны:

- [Node Exporter Full](https://grafana.killeik.net/d/node-exporter-full):
  [Grafana 1860 revision 45](https://grafana.com/grafana/dashboards/1860-node-exporter-full/),
  [JSON](https://grafana.com/api/dashboards/1860/revisions/45/download).
  Upstream rfmoz/grafana-dashboards, Apache-2.0.
- [OpenWrt](https://grafana.killeik.net/d/openwrt):
  [Grafana 18153 revision 4](https://grafana.com/grafana/dashboards/18153-asus-openwrt-router/),
  [JSON](https://grafana.com/api/dashboards/18153/revisions/4/download).
- Существующий Qingping Air остается на прежнем UID qingping-air.

Upstream панели сохранены. Для provisioning изменены только datasource UID,
dashboard UID и selectors datasource/job; import inputs удалены. Набор доступных
панелей зависит от оборудования. На OpenWrt нет inode/disk I/O; NAT traffic
accounting не включен ради dashboard, соответствующие панели останутся пустыми.
Часть необязательных Wi-Fi counters драйвер не публикует. Filesystem collector
этого релиза добавлен отдельно: /overlay и / доступны, readonly /rom не алертится.

## Telegram

Общий существующий contact point qingping-telegram использует прежний бот и
/var/lib/qingping/telegram.env. Значения не включать в Nix/store/Git.
Инфраструктурные правила находятся в grafana/host-alerts.nix; Qingping thresholds
и стиль восстановлений "Все, молчу." сохранены. Проверка раз в минуту, повтор
через 4 часа. Условия:

| Условие | Длительность |
| --- | --- |
| Недоступен exporter oggy или OpenWrt | 5 минут |
| CPU выше 90% | 15 минут |
| Использовано больше 90% RAM с учетом MemAvailable | 15 минут |
| Меньше 10% свободного места на writable диске | 15 минут |
| Systemd unit в failed на oggy/sparky | 5 минут |
| Conntrack OpenWrt заполнен больше 80% | 5 минут |

По решению пользователя выключение/сон sparky не вызывает алерт; ресурсы и
systemd errors проверяются, когда метрики доступны. Отсутствие данных для
ресурсных правил считается OK, отдельный up проверяет oggy/OpenWrt exporters.

Полное падение oggy (где работают Prometheus/Grafana) или домашнего интернета
не сможет отправить Telegram через этот же стек. Для этого нужен независимый
внешний наблюдатель. Здесь второй мониторинг не создается.
