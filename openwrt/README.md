# OpenWrt

Установить [90-conntrack-tuning.conf](90-conntrack-tuning.conf)
в `/etc/sysctl.d/90-conntrack-tuning.conf` на роутере, затем:

```sh
chmod 0644 /etc/sysctl.d/90-conntrack-tuning.conf
sysctl -p /etc/sysctl.d/90-conntrack-tuning.conf
```

Проверить загрузку таблицы соединений:

```sh
sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max
```

Откат таймаутов: удалить строки таймаутов из файла и применить прежние значения:

```sh
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_syn_sent=120
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=120
```

Не очищать conntrack: это прервет активные соединения.
