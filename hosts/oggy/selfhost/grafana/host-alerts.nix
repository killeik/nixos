{ ... }:

let
  alertRule = import ./alert-rule.nix;
in
{
  services.grafana.provision.alerting = {
    rules.settings.groups = [
      {
        orgId = 1;
        name = "Infrastructure";
        folder = "Home";
        interval = "1m";
        rules = map alertRule [
          {
            uid = "host-exporter-down";
            panelId = 15;
            title = "Нет метрик хоста";
            # Sparky is allowed to sleep or be switched off without notifications.
            expr = ''up{job=~"node|openwrt|headscale|qingping|blackbox|grafana|prometheus",host!="sparky"}'';
            condition = "$A < 1";
            duration = "5m";
            severity = "critical";
            description = "От {{ $labels.job }} ({{ $labels.instance }}) давно ничего не слышно.";
            summary = "Нет метрик больше 5 минут.";
          }
          {
            uid = "host-cpu-high";
            panelId = 20;
            title = "Долго занят процессор";
            expr = ''(100 * (1 - avg by (host, instance) (rate(node_cpu_seconds_total{job="node",mode="idle"}[5m])))) and on (host, instance) (up{job="node"} == 1)'';
            condition = "$A > 90";
            duration = "15m";
            description = "На {{ $labels.host }} процессор долго занят.";
            summary = ''CPU: {{ printf "%.1f" $values.A.Value }}%.'';
          }
          {
            uid = "host-memory-high";
            panelId = 16;
            title = "Мало свободной памяти";
            expr = ''(100 * (1 - node_memory_MemAvailable_bytes{job="node"} / node_memory_MemTotal_bytes{job="node"})) and on (host, instance) (up{job="node"} == 1)'';
            condition = "$A > 90";
            duration = "15m";
            description = "На {{ $labels.host }} мало свободной памяти.";
            summary = ''Занято: {{ printf "%.1f" $values.A.Value }}%.'';
          }
          {
            uid = "host-disk-low";
            panelId = 154;
            title = "Заканчивается место";
            expr = ''((100 * node_filesystem_avail_bytes{job="node",fstype!~"tmpfs|devtmpfs|overlay|squashfs|ramfs",mountpoint!~"/(run|var/lib/(docker|containers|nixos-containers))(/.*)?"} / node_filesystem_size_bytes{job="node"}) and on (instance, device, mountpoint) (node_filesystem_readonly{job="node"} == 0)) and on (host, instance) (up{job="node"} == 1)'';
            condition = "$A < 10";
            duration = "15m";
            description = "На {{ $labels.host }} заканчивается место.";
            summary = ''{{ $labels.mountpoint }}: {{ printf "%.1f" $values.A.Value }}% свободно.'';
          }
          {
            uid = "host-systemd-failed";
            panelId = 15;
            title = "Ошибка системной службы";
            expr = ''(node_systemd_unit_state{job="node",state="failed"} == 1) and on (host, instance) (up{job="node"} == 1)'';
            condition = "$A > 0";
            duration = "5m";
            description = "На {{ $labels.host }} не запустилась служба.";
            summary = "{{ $labels.name }} находится в failed больше 5 минут.";
          }
          {
            uid = "router-cpu-high";
            panelId = 20;
            title = "Долго занят процессор роутера";
            expr = ''100 * (1 - avg by (host, instance) (rate(node_cpu_seconds_total{job="openwrt",mode="idle"}[5m])))'';
            condition = "$A > 90";
            duration = "15m";
            dashboard = "openwrt";
            description = "Роутер долго занят.";
            summary = ''CPU: {{ printf "%.1f" $values.A.Value }}%.'';
          }
          {
            uid = "router-memory-high";
            panelId = 16;
            title = "Мало памяти на роутере";
            expr = ''100 * (1 - node_memory_MemAvailable_bytes{job="openwrt"} / node_memory_MemTotal_bytes{job="openwrt"})'';
            condition = "$A > 90";
            duration = "15m";
            dashboard = "openwrt";
            description = "На роутере мало свободной памяти.";
            summary = ''Занято: {{ printf "%.1f" $values.A.Value }}%.'';
          }
          {
            uid = "router-disk-low";
            panelId = 154;
            title = "Заканчивается место на роутере";
            expr = ''100 * node_filesystem_avail_bytes{job="openwrt",mountpoint="/overlay"} / node_filesystem_size_bytes{job="openwrt",mountpoint="/overlay"}'';
            condition = "$A < 10";
            duration = "15m";
            dashboard = "openwrt";
            description = "На роутере заканчивается место.";
            summary = ''/overlay: {{ printf "%.1f" $values.A.Value }}% свободно.'';
          }
          {
            uid = "router-conntrack-high";
            panelId = 15;
            title = "Заполняется таблица соединений";
            expr = ''100 * node_nf_conntrack_entries{job="openwrt"} / node_nf_conntrack_entries_limit{job="openwrt"}'';
            condition = "$A > 80";
            duration = "5m";
            dashboard = "openwrt";
            description = "В таблице соединений роутера тесно.";
            summary = ''Conntrack: {{ printf "%.1f" $values.A.Value }}%.'';
          }
          # Adapted from node-mixin and Awesome Prometheus Alerts; thresholds fit live metrics.
          # https://github.com/prometheus/node_exporter/tree/master/docs/node-mixin
          # https://samber.github.io/awesome-prometheus-alerts/rules.html
          {
            uid = "host-oom-kill";
            title = "OOM завершил процесс";
            expr = ''increase(node_vmstat_oom_kill{job="node"}[30m]) and on (host, instance) (up{job="node"} == 1)'';
            condition = "$A > 0";
            duration = "0m";
            description = "На {{ $labels.host }} закончилась память.";
            summary = "Ядро завершало процессы из-за нехватки памяти за последние 30 минут.";
            dashboard = "node-exporter-full";
            panelId = 307;
            severity = "warning";
          }
          {
            uid = "host-filesystem-readonly";
            title = "Файловая система стала read-only";
            # /nix/store is intentionally read-only. Keep the Btrfs root in scope.
            expr = ''node_filesystem_readonly{job="node",fstype=~"btrfs|ext[234]|xfs|vfat",mountpoint!~"/nix/store|/(run|var/lib/(docker|containers|nixos-containers))(/.*)?"} and on (host, instance) (up{job="node"} == 1)'';
            condition = "$A > 0";
            duration = "2m";
            description = "На {{ $labels.host }} файловая система {{ $labels.mountpoint }} стала read-only.";
            summary = "{{ $labels.device }} недоступно для записи больше 2 минут.";
            dashboard = "node-exporter-full";
            panelId = 44;
            severity = "critical";
          }
          {
            uid = "host-filesystem-stat-error";
            title = "Не читается статистика файловой системы";
            # This is a statfs failure, not a disk read/write error counter.
            expr = ''node_filesystem_device_error{job="node",fstype=~"btrfs|ext[234]|xfs|vfat",mountpoint!~"/nix/store|/(run|var/lib/(docker|containers|nixos-containers))(/.*)?"} and on (host, instance) (up{job="node"} == 1)'';
            condition = "$A > 0";
            duration = "5m";
            description = "На {{ $labels.host }} не читается {{ $labels.mountpoint }}.";
            summary = "Статистика файловой системы недоступна больше 5 минут.";
            dashboard = "node-exporter-full";
            panelId = 44;
            severity = "warning";
          }
          {
            uid = "host-temperature-limit";
            title = "Датчик сообщает о перегреве";
            # Prefer the driver's max limit; use crit only for sensors without max.
            expr = ''(node_hwmon_temp_celsius{job="node"} - ((node_hwmon_temp_max_celsius{job="node"} > 0) or (node_hwmon_temp_crit_celsius{job="node"} > 0))) and on (host, instance) (up{job="node"} == 1)'';
            condition = "$A > 0";
            duration = "5m";
            description = "На {{ $labels.host }} датчику {{ $labels.chip }}/{{ $labels.sensor }} слишком жарко.";
            summary = ''Температура выше аппаратного порога на {{ printf "%.1f" $values.A.Value }} C больше 5 минут.'';
            dashboard = "node-exporter-full";
            panelId = 158;
            severity = "warning";
          }
          {
            uid = "host-btrfs-device-errors";
            title = "Новые ошибки Btrfs";
            expr = ''increase(node_btrfs_device_errors_total{job="node"}[15m]) and on (host, instance) (up{job="node"} == 1)'';
            condition = "$A > 0";
            duration = "0m";
            description = "На {{ $labels.host }} появились ошибки Btrfs: {{ $labels.type }}, {{ $labels.device }}.";
            summary = "Счетчик ошибок {{ $labels.uuid }} вырос за последние 15 минут.";
            dashboard = "node-exporter-full";
            # Context only: this existing panel does not graph Btrfs device counters.
            panelId = 44;
            severity = "critical";
          }
          {
            uid = "caddy-unavailable";
            title = "Нет метрик Caddy";
            expr = ''up{job="caddy"} or on () absent(up{job="caddy"}) * 0'';
            condition = "$A < 1";
            duration = "5m";
            severity = "critical";
            dashboard = "caddy";
            panelId = 28;
            description = "Caddy на oggy не отвечает.";
            summary = "Нет метрик больше 5 минут.";
          }
          {
            uid = "caddy-high-5xx";
            title = "Caddy возвращает ошибки";
            # At least 20 completed proxy requests per host in 5m, then >5% errors for 10m.
            # Caddy labels our HTTPS site routes as subroute; count them once at the outer route.
            # Duration counts carry HTTP status, unlike caddy_http_requests_total.
            expr = ''(100 * sum by (host) (rate(caddy_http_request_duration_seconds_count{job="caddy",handler="subroute",code=~"5.."}[5m])) / sum by (host) (rate(caddy_http_request_duration_seconds_count{job="caddy",handler="subroute"}[5m]))) and on (host) (sum by (host) (increase(caddy_http_request_duration_seconds_count{job="caddy",handler="subroute"}[5m])) >= 20)'';
            condition = "$A > 5";
            duration = "10m";
            dashboard = "caddy";
            panelId = 31;
            description = "У {{ $labels.host }} слишком много ошибок 5xx.";
            summary = ''5xx: {{ printf "%.1f" $values.A.Value }}% больше 10 минут (не менее 20 запросов за 5 минут).'';
          }

          {
            uid = "service-http-down";
            title = "Сервис не отвечает";
            condition = "$A < 1";
            duration = "3m";
            description = "Сервис {{ $labels.service }} не отвечает через HTTPS.";
            summary = "Проверка через Caddy не проходит больше 3 минут.";
            dashboard = "service-health";
            severity = "critical";
            expr = ''probe_success{job="blackbox"}'';
            panelId = 1;
          }
          {
            uid = "service-tls-expiring";
            title = "Скоро истечет сертификат";
            condition = "$A < 14";
            duration = "15m";
            description = "Сертификат {{ $labels.service }} скоро истечет.";
            summary = ''Осталось {{ printf "%.1f" $values.A.Value }} дней.'';
            dashboard = "service-health";
            severity = "warning";
            expr = ''(probe_ssl_earliest_cert_expiry{job="blackbox"} - time()) / 86400'';
            panelId = 3;
          }
          {
            uid = "backup-stale";
            title = "Давно не было резервной копии";
            condition = "$A > 129600";
            duration = "15m";
            description = "На oggy давно не было успешной резервной копии.";
            summary = "Нет подтвержденного завершения dumps и snapshots больше 36 часов.";
            dashboard = "service-health";
            severity = "critical";
            expr = ''time() - (max(oggy_backup_last_success_timestamp_seconds{job="node",host="oggy"}) or vector(0))'';
            panelId = 4;
          }
          {
            uid = "monitoring-textfile-error";
            title = "Ошибка метрик резервного копирования";
            condition = "$A > 0";
            duration = "5m";
            description = "На oggy не читаются textfile-метрики.";
            summary = "Проверь файл btrbk.prom: ошибка сохраняется больше 5 минут.";
            dashboard = "service-health";
            severity = "warning";
            expr = ''node_textfile_scrape_error{job="node",host="oggy"}'';
            panelId = 4;
          }
          {
            uid = "monitoring-evaluation-errors";
            title = "Ошибки вычисления алертов";
            condition = "$A > 0";
            duration = "5m";
            description = "Grafana не может вычислить часть алертов.";
            summary = "Ошибки вычисления в последние 10 минут.";
            dashboard = "service-health";
            severity = "warning";
            expr = ''sum(increase(grafana_alerting_rule_evaluation_failures_total{job="grafana"}[10m])) or vector(0)'';
            panelId = 6;
          }
        ];
      }
    ];
  };
}
