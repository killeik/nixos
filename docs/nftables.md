# Переход oggy на nftables

NixOS управляет таблицами `nixos-fw`, `nixos-nat`, `codex-guard` и
`slskd-guard`; `flushRuleset = false` сохраняет таблицы Docker при reload.
Docker 29.8.2 остается на стабильном iptables backend (iptables-nft).
Его native nftables backend пока experimental и здесь не используется.
NixOS запрещает посторонний forwarding, разрешает established, DNAT,
исходящий трафик Docker bridges и Codex NAT. Docker сохраняет проверку
опубликованных портов и изоляцию bridges. Guards с priority -10 выполняются
раньше filter chains; их reject нельзя отменить последующим accept.

Slskd: 256 отслеживаемых исходящих TCP-соединений, 8 новых SYN/second,
burst 25. Reload пересоздает dynamic set и token bucket: ранее открытые
соединения новый set не считает и не разрывает. Не делать reload во время
шторма соединений. Прежний iptables connlimit также терял состояние при
пересоздании правила. Не добавлять ve-codex в trusted interfaces.

## Первая активация и откат

Нужно окно обслуживания, доступ к консоли и сохраненное предыдущее поколение.
После проверок и сборки использовать `nixos-rebuild boot` с обычными
аргументами flake/target-host oggy, затем перезагрузить сервер. Первый переход
через `switch` не использовать: старый iptables FORWARD DROP может остаться
и заблокировать Codex несмотря на nft accept. Чистая загрузка удаляет старые
CODEX-EGRESS/SLSKD-GUARD и NAT; `ip-forward-no-drop` оставляет iptables policy
ACCEPT, а ограничительную forward policy задает NixOS nftables.
Перезагрузка прерывает все сервисы и соединения.

После загрузки проверить SSH во втором соединении, `systemctl --failed`,
`systemctl status nftables docker container@codex`, `nft list ruleset` и
`iptables -S FORWARD` (policy ACCEPT). Проверить Codex DNS TCP/UDP к
192.168.1.1, internet, запрет LAN/host; Docker published ports и Slskd.
Повторить проверку портов после reload nftables: таблицы Docker сохраняются.

Откат: загрузить предыдущее поколение NixOS и закрепить его обычной процедурой
rollback/boot. Откат тоже выполнять с перезагрузкой, чтобы оба backend
получили чистое состояние ядра. Не выполнять flush ruleset и не удалять
таблицы Docker вручную.

Проверены pinned nixpkgs 09063bd1f2b36fd9fd793c36dfade7bd40a93dfc,
модули networking/{nftables,firewall-nftables,nat-nftables}.nix,
virtualisation/docker.nix и package definition Docker; документация:

- https://docs.docker.com/engine/network/packet-filtering-firewalls/
- https://docs.docker.com/engine/network/firewall-nftables/
- https://wiki.nftables.org/wiki-nftables/index.php/Configuring_chains
- https://wiki.nftables.org/wiki-nftables/index.php/Meters
- https://netfilter.org/projects/nftables/manpage.html
