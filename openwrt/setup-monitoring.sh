#!/bin/sh
# Run on the router with filesystem.lua next to this script.
set -eu
cd "$(dirname "$0")"

opkg update
opkg install prometheus-node-exporter-lua \
  prometheus-node-exporter-lua-openwrt \
  prometheus-node-exporter-lua-wifi prometheus-node-exporter-lua-wifi_stations
cp filesystem.lua /usr/lib/lua/prometheus-collectors/filesystem.lua
chmod 0644 /usr/lib/lua/prometheus-collectors/filesystem.lua

# Both rules must be global: fw4 evaluates these before zone input rules.
# LAN input is ACCEPT, so the reject is needed to make the source exclusive.
uci -q delete firewall.node_exporter_oggy || true
uci -q delete firewall.node_exporter_reject || true
uci batch <<'EOF'
set firewall.node_exporter_oggy=rule
set firewall.node_exporter_oggy.name='Node exporter from oggy'
set firewall.node_exporter_oggy.src='*'
set firewall.node_exporter_oggy.device='br-lan'
set firewall.node_exporter_oggy.direction='in'
set firewall.node_exporter_oggy.src_ip='192.168.1.2'
set firewall.node_exporter_oggy.dest_ip='192.168.1.1'
set firewall.node_exporter_oggy.proto='tcp'
set firewall.node_exporter_oggy.dest_port='9100'
set firewall.node_exporter_oggy.family='ipv4'
set firewall.node_exporter_oggy.target='ACCEPT'
set firewall.node_exporter_reject=rule
set firewall.node_exporter_reject.name='Reject other node exporter sources'
set firewall.node_exporter_reject.src='*'
set firewall.node_exporter_reject.proto='tcp'
set firewall.node_exporter_reject.dest_port='9100'
set firewall.node_exporter_reject.target='REJECT'
reorder firewall.node_exporter_oggy=0
reorder firewall.node_exporter_reject=1
EOF
fw4 check
uci commit firewall
/etc/init.d/firewall reload

uci set prometheus-node-exporter-lua.main.listen_interface='lan'
uci set prometheus-node-exporter-lua.main.listen_port='9100'
uci commit prometheus-node-exporter-lua
/etc/init.d/prometheus-node-exporter-lua enable
/etc/init.d/prometheus-node-exporter-lua restart
