{ ... }:

let
  alertRule =
    {
      uid,
      title,
      expr,
      condition,
      duration,
      description,
      summary,
      dashboard ? "node-exporter-full",
      severity ? "warning",
    }:
    {
      inherit uid title;
      condition = "B";
      for = duration;
      noDataState = "OK";
      execErrState = "Error";
      labels = {
        inherit severity;
        scope = "infrastructure";
      };
      annotations = {
        inherit description summary;
        __dashboardUid__ = dashboard;
      };
      notification_settings = {
        # Keep the existing contact point UID and credentials during this expansion.
        receiver = "qingping-telegram";
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "4h";
      };
      data = [
        {
          refId = "A";
          datasourceUid = "PBFA97CFB590B2093";
          relativeTimeRange = {
            from = 300;
            to = 0;
          };
          model = {
            refId = "A";
            inherit expr;
            instant = true;
            range = false;
          };
        }
        {
          refId = "B";
          datasourceUid = "__expr__";
          relativeTimeRange = {
            from = 0;
            to = 0;
          };
          model = {
            refId = "B";
            type = "math";
            expression = condition;
          };
        }
      ];
    };
in
{
  systemd.services.grafana.serviceConfig.EnvironmentFile = "/var/lib/qingping/telegram.env";

  services.grafana.provision.alerting = {
    contactPoints.settings.contactPoints = [
      {
        orgId = 1;
        name = "qingping-telegram";
        receivers = [
          {
            uid = "qingping-telegram";
            type = "telegram";
            disableResolveMessage = false;
            settings = {
              bottoken = "$QINGPING_TELEGRAM_TOKEN";
              chatid = "$QINGPING_TELEGRAM_CHAT_ID";
              parse_mode = "None";
              disable_web_page_preview = true;
              message = ''
                {{ range .Alerts }}
                {{ if eq .Status "firing" }}{{ .Annotations.description }}{{ else }}Все, молчу.{{ end }}
                {{ .Annotations.summary }}
                {{ .DashboardURL }}
                {{ end }}
              '';
            };
          }
        ];
      }
    ];
    rules.settings.groups = [
      {
        orgId = 1;
        name = "Infrastructure";
        folder = "Home";
        interval = "1m";
        rules = map alertRule [
          {
            uid = "host-exporter-down";
            title = "Нет метрик хоста";
            # Sparky is allowed to sleep or be switched off without notifications.
            expr = ''up{job=~"node|openwrt",host!="sparky"}'';
            condition = "$A < 1";
            duration = "5m";
            severity = "critical";
            description = "От {{ $labels.host }} давно ничего не слышно.";
            summary = "Нет метрик больше 5 минут.";
          }
          {
            uid = "host-cpu-high";
            title = "Долго занят процессор";
            expr = ''100 * (1 - avg by (host, instance) (rate(node_cpu_seconds_total{job="node",mode="idle"}[5m])))'';
            condition = "$A > 90";
            duration = "15m";
            description = "На {{ $labels.host }} процессор долго занят.";
            summary = ''CPU: {{ printf "%.1f" $values.A.Value }}%.'';
          }
          {
            uid = "host-memory-high";
            title = "Мало свободной памяти";
            expr = ''100 * (1 - node_memory_MemAvailable_bytes{job="node"} / node_memory_MemTotal_bytes{job="node"})'';
            condition = "$A > 90";
            duration = "15m";
            description = "На {{ $labels.host }} мало свободной памяти.";
            summary = ''Занято: {{ printf "%.1f" $values.A.Value }}%.'';
          }
          {
            uid = "host-disk-low";
            title = "Заканчивается место";
            expr = ''(100 * node_filesystem_avail_bytes{job="node",fstype!~"tmpfs|devtmpfs|overlay|squashfs|ramfs",mountpoint!~"/(run|var/lib/(docker|containers|nixos-containers))(/.*)?"} / node_filesystem_size_bytes{job="node"}) and on (instance, device, mountpoint) (node_filesystem_readonly{job="node"} == 0)'';
            condition = "$A < 10";
            duration = "15m";
            description = "На {{ $labels.host }} заканчивается место.";
            summary = ''{{ $labels.mountpoint }}: {{ printf "%.1f" $values.A.Value }}% свободно.'';
          }
          {
            uid = "host-systemd-failed";
            title = "Ошибка системной службы";
            expr = ''node_systemd_unit_state{job="node",state="failed"} == 1'';
            condition = "$A > 0";
            duration = "5m";
            description = "На {{ $labels.host }} не запустилась служба.";
            summary = "{{ $labels.name }} находится в failed больше 5 минут.";
          }
          {
            uid = "router-cpu-high";
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
            title = "Заполняется таблица соединений";
            expr = ''100 * node_nf_conntrack_entries{job="openwrt"} / node_nf_conntrack_entries_limit{job="openwrt"}'';
            condition = "$A > 80";
            duration = "5m";
            dashboard = "openwrt";
            description = "В таблице соединений роутера тесно.";
            summary = ''Conntrack: {{ printf "%.1f" $values.A.Value }}%.'';
          }
        ];
      }
    ];
  };
}
