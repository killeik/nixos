# OpenWrt conntrack tuning

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
