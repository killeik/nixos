{ pkgs, oggy, ... }:

let
  mqtt2prometheus = pkgs.buildGoModule {
    pname = "mqtt2prometheus";
    version = "unstable-2026-02-16";
    src = pkgs.fetchFromGitHub {
      owner = "hikhvar";
      repo = "mqtt2prometheus";
      rev = "c324374c71ae1102c450d310e8efbbe8db9cbcb5";
      hash = "sha256-HJnE2eKa2SXGa99YuzUxi2PONyA2kIuHpbzOoHzGRDg=";
    };
    vendorHash = "sha256-ceQ3M9C/Bk+3WzKfk6t/OBNLV/4YbBvtb4vNIVW2Y/0=";
    subPackages = [ "cmd" ];
    env.CGO_ENABLED = 0;
    ldflags = [
      "-s"
      "-w"
    ];
    postInstall = ''
      mv $out/bin/cmd $out/bin/mqtt2prometheus
    '';
  };

  exporterConfig = (pkgs.formats.yaml { }).generate "qingping-mqtt.yaml" {
    mqtt = {
      server = "tcp://${oggy.lanAddress}:1883";
      user = "qingping-metrics";
      client_id = "qingping-prometheus";
      topic_path = "qingping/${oggy.qingpingDeviceId}/up";
      device_id_regex = "qingping/(?P<deviceid>[^/]+)/up";
      qos = 1;
    };
    cache.timeout = "3m";
    metrics =
      map
        (metric: {
          prom_name = "qingping_${metric.name}";
          mqtt_name = "sensorData.[0].${metric.field}.value";
          help = metric.help;
          type = "gauge";
        })
        [
          {
            name = "co2_ppm";
            field = "co2";
            help = "Carbon dioxide concentration in ppm.";
          }
          {
            name = "pm25_micrograms_per_cubic_meter";
            field = "pm25";
            help = "PM2.5 concentration in micrograms per cubic meter.";
          }
          {
            name = "pm10_micrograms_per_cubic_meter";
            field = "pm10";
            help = "PM10 concentration in micrograms per cubic meter.";
          }
          {
            name = "temperature_celsius";
            field = "temperature";
            help = "Air temperature in degrees Celsius.";
          }
          {
            name = "humidity_percent";
            field = "humidity";
            help = "Relative humidity in percent.";
          }
          {
            name = "battery_percent";
            field = "battery";
            help = "Battery charge in percent.";
          }
        ];
  };

  alertRule =
    {
      uid,
      title,
      metric,
      condition,
      duration,
      description,
      summary,
      panelId,
    }:
    {
      inherit uid title;
      condition = "B";
      for = duration;
      noDataState = "OK";
      execErrState = "Error";
      annotations = {
        inherit description summary;
        __dashboardUid__ = "qingping-air";
        __panelId__ = toString panelId;
      };
      notification_settings = {
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
            from = 180;
            to = 0;
          };
          model = {
            refId = "A";
            expr = "${metric}{job=\"qingping\"}";
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
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = oggy.lanAddress;
        users.qingping = {
          passwordFile = "/var/lib/qingping/mqtt-password";
          acl = [ "readwrite qingping/${oggy.qingpingDeviceId}/#" ];
        };
        users.qingping-metrics = {
          passwordFile = "/var/lib/qingping/metrics-password";
          acl = [ "read qingping/${oggy.qingpingDeviceId}/up" ];
        };
      }
    ];
  };

  networking.firewall.allowedTCPPorts = [ 1883 ];

  systemd.services.qingping-exporter = {
    description = "Qingping MQTT to Prometheus exporter";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "mosquitto.service"
    ];
    wants = [ "network-online.target" ];
    environment.MQTT2PROM_MQTT_PASSWORD = "%d/mqtt-password";
    serviceConfig = {
      ExecStart = "${mqtt2prometheus}/bin/mqtt2prometheus -config=${exporterConfig} -listen-address=127.0.0.1 -listen-port=9641 -treat-mqtt-password-as-file-name";
      DynamicUser = true;
      LoadCredential = "mqtt-password:/var/lib/qingping/metrics-password";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  # The device grants a reporting session for one hour. Retaining the request
  # also restores reporting when the monitor reconnects to the broker.
  systemd.services.qingping-reporting = {
    description = "Renew Qingping measurement reporting";
    after = [ "mosquitto.service" ];
    requires = [ "mosquitto.service" ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      LoadCredential = "mqtt-password:/var/lib/qingping/mqtt-password";
      RuntimeDirectory = "qingping-reporting";
      RuntimeDirectoryMode = "0700";
      TimeoutStartSec = 20;
    };
    script = ''
      umask 077
      printf -- '-P %s\n' "$(cat "$CREDENTIALS_DIRECTORY/mqtt-password")" > "$RUNTIME_DIRECTORY/mosquitto.conf"
      exec ${pkgs.mosquitto}/bin/mosquitto_pub -o "$RUNTIME_DIRECTORY/mosquitto.conf" \
        -h ${oggy.lanAddress} -u qingping -q 1 -r -t qingping/${oggy.qingpingDeviceId}/down \
        -m '{"type":"12","up_itvl":"60","duration":"3600"}'
    '';
  };

  systemd.timers.qingping-reporting = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "5s";
      OnUnitActiveSec = "50m";
    };
  };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "qingping";
      scrape_interval = "15s";
      static_configs = [ { targets = [ "127.0.0.1:9641" ]; } ];
    }
  ];

  services.grafana.provision.dashboards.settings.providers = [
    {
      name = "qingping";
      folder = "Home";
      options.path = ./grafana/dashboards;
    }
  ];

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
        name = "Qingping";
        folder = "Home";
        interval = "1m";
        rules = map alertRule [
          {
            uid = "qingping-co2-high";
            title = "Высокий CO2";
            metric = "qingping_co2_ppm";
            condition = "$A > 1500";
            duration = "10m";
            description = "Я тут тоже живу. Открой окно.";
            summary = ''CO2: {{ printf "%.0f" $values.A.Value }} ppm.'';
            panelId = 1;
          }
          {
            uid = "qingping-humidity-low";
            title = "Низкая влажность";
            metric = "qingping_humidity_percent";
            condition = "$A < 30";
            duration = "30m";
            description = "Низкая влажность.";
            summary = ''Влажность: {{ printf "%.0f" $values.A.Value }}%.'';
            panelId = 5;
          }
          {
            uid = "qingping-humidity-high";
            title = "Высокая влажность";
            metric = "qingping_humidity_percent";
            condition = "$A > 60";
            duration = "30m";
            description = "Хозяин, сыровато. У нас тут кто-то прорастает.";
            summary = ''Влажность: {{ printf "%.0f" $values.A.Value }}%.'';
            panelId = 5;
          }
        ];
      }
    ];
  };

}
