{ pkgs, oggy, ... }:

let
  mqtt2prometheus = pkgs.callPackage ../../../packages/mqtt2prometheus { };

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

  alertRule = import ./grafana/alert-rule.nix;
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

  services.grafana.provision.alerting = {
    rules.settings.groups = [
      {
        orgId = 1;
        name = "Qingping";
        folder = "Home";
        interval = "1m";
        rules =
          map
            (
              rule:
              alertRule (
                {
                  dashboard = "qingping-air";
                  timeRange = 180;
                  labels = null;
                }
                // rule
              )
            )
            [
              {
                uid = "qingping-co2-high";
                title = "Высокий CO2";
                expr = ''qingping_co2_ppm{job="qingping"}'';
                condition = "$A > 1500";
                duration = "10m";
                description = "Я тут тоже живу. Открой окно.";
                summary = ''CO2: {{ printf "%.0f" $values.A.Value }} ppm.'';
                panelId = 1;
              }
              {
                uid = "qingping-humidity-low";
                title = "Низкая влажность";
                expr = ''qingping_humidity_percent{job="qingping"}'';
                condition = "$A < 35";
                duration = "30m";
                description = "Низкая влажность.";
                summary = ''Влажность: {{ printf "%.0f" $values.A.Value }}%.'';
                panelId = 5;
              }
              {
                uid = "qingping-humidity-high";
                title = "Высокая влажность";
                expr = ''qingping_humidity_percent{job="qingping"}'';
                condition = "$A > 55";
                duration = "30m";
                description = "Хозяин, сыровато. У нас тут кто-то прорастает.";
                summary = ''Влажность: {{ printf "%.0f" $values.A.Value }}%.'';
                panelId = 5;
              }
            ]
          ++ map alertRule [
            {
              uid = "qingping-data-stale";
              title = "Нет свежих показаний Qingping";
              condition = "$A > 600";
              duration = "5m";
              description = "Датчик Qingping давно молчит.";
              summary = "Нет свежих показаний CO2 больше 10 минут.";
              dashboard = "service-health";
              severity = "warning";
              expr = ''time() - (max(max_over_time(timestamp(qingping_co2_ppm{job="qingping"})[1h:1m])) or vector(0))'';
              panelId = 5;
            }
            {
              uid = "qingping-mqtt-disconnected";
              title = "Экспортер потерял MQTT";
              condition = "$A < 1";
              duration = "3m";
              description = "Экспортер Qingping потерял связь с MQTT.";
              summary = "Соединение не восстановилось за 3 минуты.";
              dashboard = "service-health";
              severity = "warning";
              expr = ''mqtt2prometheus_connected{job="qingping"}'';
              panelId = 5;
            }
          ];
      }
    ];
  };

}
