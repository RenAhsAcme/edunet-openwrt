#!/bin/sh
set -eu
[ "$(id -u)" = 0 ] || exit 1
umask 077
backup="/root/wan-ip-pool-persistence-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
[ ! -f /etc/sysupgrade.conf ] || cp /etc/sysupgrade.conf "$backup/sysupgrade.conf"
touch /etc/sysupgrade.conf
for path in /usr/sbin/wan-ip-pool-auto /usr/lib/wan-ip-pool-auto/ /etc/wan-ip-pool-auto.conf /etc/hotplug.d/iface/95-wan-ip-pool-auto /etc/crontabs/root /root/wan-ip-pool.sh; do
    grep -qxF "$path" /etc/sysupgrade.conf || printf '%s\n' "$path" >> /etc/sysupgrade.conf
done
/etc/init.d/cron enable
echo "Persistence backup: $backup"
