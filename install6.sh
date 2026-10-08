#!/bin/sh
set -eu
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || exit 1
for cmd in lua ubus jsonfilter ip nft curl awk flock sha256sum logger;do
    command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd";exit 1; }
done
umask 077
backup="/root/wan-ipv6-pool-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup" /usr/lib/wan-ip-pool-auto /etc/crontabs /etc/hotplug.d/iface
for path in /usr/sbin/wan-ipv6-pool-auto /usr/lib/wan-ip-pool-auto/netcalc6.lua /etc/wan-ipv6-pool-auto.conf /etc/hotplug.d/iface/96-wan-ipv6-pool-auto /root/wan-ipv6-pool.sh /etc/crontabs/root /etc/sysupgrade.conf;do
    [ ! -f "$path" ] || cp "$path" "$backup/$(echo "$path" | tr / _)"
done
ip -6 addr show > "$backup/addresses6"
ip -6 route show table all > "$backup/routes6"
nft list ruleset > "$backup/ruleset.nft"
cp netcalc6.lua /usr/lib/wan-ip-pool-auto/
cp wan-ipv6-pool-auto /usr/sbin/wan-ipv6-pool-auto.new
chmod 700 /usr/sbin/wan-ipv6-pool-auto.new
mv /usr/sbin/wan-ipv6-pool-auto.new /usr/sbin/wan-ipv6-pool-auto
[ -f /etc/wan-ipv6-pool-auto.conf ] || cp wan-ipv6-pool-auto.conf /etc/wan-ipv6-pool-auto.conf
chmod 600 /etc/wan-ipv6-pool-auto.conf
cp hotplug-iface6 /etc/hotplug.d/iface/96-wan-ipv6-pool-auto
chmod 700 /etc/hotplug.d/iface/96-wan-ipv6-pool-auto
cat > /root/wan-ipv6-pool.sh <<'WRAPPER'
#!/bin/sh
case "${1:-status}" in
 stop) sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/wan-ipv6-pool-auto.conf;exec /usr/sbin/wan-ipv6-pool-auto clear;;
 apply) sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/wan-ipv6-pool-auto.conf;exec /usr/sbin/wan-ipv6-pool-auto refresh;;
 *) exec /usr/sbin/wan-ipv6-pool-auto "${1:-status}";;
esac
WRAPPER
chmod 700 /root/wan-ipv6-pool.sh
touch /etc/crontabs/root
grep -v '_WAN_IPV6_POOL_AUTO_' /etc/crontabs/root > /etc/crontabs/root.awp6-new || :
printf '%s\n' '* * * * * /usr/sbin/wan-ipv6-pool-auto check >/dev/null 2>&1 # _WAN_IPV6_POOL_AUTO_' >> /etc/crontabs/root.awp6-new
chmod 600 /etc/crontabs/root.awp6-new
mv /etc/crontabs/root.awp6-new /etc/crontabs/root
touch /etc/sysupgrade.conf
for path in /usr/sbin/wan-ipv6-pool-auto /usr/lib/wan-ip-pool-auto/ /etc/wan-ipv6-pool-auto.conf /etc/hotplug.d/iface/96-wan-ipv6-pool-auto /root/wan-ipv6-pool.sh /etc/crontabs/root;do
    grep -qxF "$path" /etc/sysupgrade.conf || printf '%s\n' "$path" >> /etc/sysupgrade.conf
done
/etc/init.d/cron enable
/etc/init.d/cron restart
echo "IPv6 backup: $backup"
exec /usr/sbin/wan-ipv6-pool-auto refresh
