# OpenWrt conntrack tuning

Soularr can request directory contents from many Soulseek peers in a short
period. Slskd turns those requests into direct TCP connection attempts. Peers
that do not answer leave `SYN_SENT` entries in the OpenWrt conntrack table, so
the router can exhaust its table even though Slskd has already timed out.

OpenWrt keeps a 32K table, expires unanswered SYN attempts after 30 seconds,
and keeps `TIME_WAIT` entries for 60 seconds. These general router settings
remain after the music stack was removed from oggy.

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

The music stack and its dedicated connection guard have been removed from oggy.
The general OpenWrt conntrack settings above remain in place.

## Rollback

On OpenWrt, keep the 32K capacity but restore the previous TCP timeouts by
leaving only the `nf_conntrack_max` line in the sysctl file and applying:

```sh
sysctl -w net.netfilter.nf_conntrack_max=32768
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_syn_sent=120
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=120
```

Do not flush the conntrack table during rollback because that interrupts
unrelated active connections.
