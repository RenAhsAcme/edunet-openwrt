#!/bin/sh
set -eu
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo 'Run as root on the OpenWrt router.'; exit 1; }
for cmd in lua ubus jsonfilter ip nft curl ping awk flock sha256sum logger; do
    command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd"; exit 1; }
done
umask 077
BACKUP="/root/wan-ip-pool-auto-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP" /usr/lib/wan-ip-pool-auto /etc/crontabs /etc/hotplug.d/iface
for f in /etc/crontabs/root /etc/wan-ip-pool-auto.conf /root/wan-ip-pool.sh /usr/sbin/wan-ip-pool-auto /usr/lib/wan-ip-pool-auto/netcalc.lua /usr/lib/wan-ip-pool-auto/nftcalc.lua /etc/hotplug.d/iface/95-wan-ip-pool-auto /etc/sysupgrade.conf; do
    [ ! -f "$f" ] || cp "$f" "$BACKUP/$(echo "$f" | tr / _)"
done
# Stop the earlier manual implementation before taking ownership of its aliases.
if [ -f /tmp/wan-ip-pool/active ]; then
    [ -x /root/wan-ip-pool.sh ] || { echo 'Stop the existing manual pool first.'; exit 1; }
    /root/wan-ip-pool.sh stop
fi
cp netcalc.lua nftcalc.lua /usr/lib/wan-ip-pool-auto/
cp wan-ip-pool-auto /usr/sbin/wan-ip-pool-auto.new
chmod 700 /usr/sbin/wan-ip-pool-auto.new
mv /usr/sbin/wan-ip-pool-auto.new /usr/sbin/wan-ip-pool-auto
[ -f /etc/wan-ip-pool-auto.conf ] || cp wan-ip-pool-auto.conf /etc/wan-ip-pool-auto.conf
chmod 600 /etc/wan-ip-pool-auto.conf
cp hotplug-iface /etc/hotplug.d/iface/95-wan-ip-pool-auto
chmod 700 /etc/hotplug.d/iface/95-wan-ip-pool-auto
touch /etc/crontabs/root
grep -v '_WAN_IP_POOL_AUTO_' /etc/crontabs/root > /etc/crontabs/root.awp-new || :
printf '%s\n' '* * * * * /usr/sbin/wan-ip-pool-auto check >/dev/null 2>&1 # _WAN_IP_POOL_AUTO_' >> /etc/crontabs/root.awp-new
chmod 600 /etc/crontabs/root.awp-new
mv /etc/crontabs/root.awp-new /etc/crontabs/root
# Preserve the previously supplied stop command, now disabling automation too.
cat > /root/wan-ip-pool.sh <<'WRAPPER'
#!/bin/sh
case "${1:-status}" in
 stop)
    sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/wan-ip-pool-auto.conf
    exec /usr/sbin/wan-ip-pool-auto clear;;
 apply)
    sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/wan-ip-pool-auto.conf
    exec /usr/sbin/wan-ip-pool-auto refresh;;
 *) exec /usr/sbin/wan-ip-pool-auto "${1:-status}";;
esac
WRAPPER
chmod 700 /root/wan-ip-pool.sh
sh ./persist.sh
/etc/init.d/cron enable
/etc/init.d/cron restart
echo "Backup: $BACKUP"
echo 'Starting discovery; existing connections using old aliases may reconnect.'
exec /usr/sbin/wan-ip-pool-auto refresh
