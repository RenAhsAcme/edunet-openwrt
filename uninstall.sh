#!/bin/sh
set -eu
[ "$(id -u)" = 0 ] || exit 1
case "${1:-}" in 4|6|all) family=$1;; *) echo 'Usage: sh uninstall.sh 4|6|all';exit 2;; esac
umask 077
backup="/root/edunet-uninstall-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
for path in /etc/crontabs/root /etc/sysupgrade.conf; do
    [ ! -f "$path" ] || cp "$path" "$backup/$(echo "$path" | tr / _)"
done
remove_family() {
    version=$1
    if [ "$version" = 4 ]; then
        engine=wan-ip-pool-auto;wrapper=wan-ip-pool.sh;hook=95-wan-ip-pool-auto;marker=_WAN_IP_POOL_AUTO_
        libraries='/usr/lib/wan-ip-pool-auto/netcalc.lua /usr/lib/wan-ip-pool-auto/nftcalc.lua'
    else
        engine=wan-ipv6-pool-auto;wrapper=wan-ipv6-pool.sh;hook=96-wan-ipv6-pool-auto;marker=_WAN_IPV6_POOL_AUTO_
        libraries='/usr/lib/wan-ip-pool-auto/netcalc6.lua'
    fi
    # 先停用并通过引擎清理其持有的地址、规则和路由。
    if [ -x "/root/$wrapper" ]; then "/root/$wrapper" stop; fi
    for path in "/usr/sbin/$engine" "/etc/$engine.conf" "/root/$wrapper" "/etc/hotplug.d/iface/$hook" $libraries; do
        if [ -f "$path" ]; then cp "$path" "$backup/$(echo "$path" | tr / _)";rm -f "$path";fi
        if [ -f /etc/sysupgrade.conf ]; then
            grep -vxF "$path" /etc/sysupgrade.conf > "$backup/sysupgrade.next" || :
            cat "$backup/sysupgrade.next" > /etc/sysupgrade.conf
        fi
    done
    if [ -f /etc/crontabs/root ]; then
        grep -v "$marker" /etc/crontabs/root > "$backup/cron.next" || :
        cat "$backup/cron.next" > /etc/crontabs/root
    fi
}
[ "$family" = 6 ] || remove_family 4
[ "$family" = 4 ] || remove_family 6
if [ ! -f /usr/sbin/wan-ip-pool-auto ] && [ ! -f /usr/sbin/wan-ipv6-pool-auto ] && [ -f /etc/sysupgrade.conf ]; then
    grep -vxF '/usr/lib/wan-ip-pool-auto/' /etc/sysupgrade.conf > "$backup/sysupgrade.next" || :
    cat "$backup/sysupgrade.next" > /etc/sysupgrade.conf
fi
/etc/init.d/cron restart
echo "Uninstalled family: $family; backup: $backup"
