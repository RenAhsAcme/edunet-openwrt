#!/bin/sh
set -eu
cd "$(dirname "$0")"
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT
export AWP6_BASE="$base"
mkdir -p "$base/mock-bin" "$base/etc" "$base/usr/lib/wan-ip-pool-auto"
cp wan-ipv6-pool-auto.conf "$base/etc/"
sed -i 's/^ENABLED=.*/ENABLED=1/' "$base/etc/wan-ipv6-pool-auto.conf"
echo POOL_SIZE=4 >> "$base/etc/wan-ipv6-pool-auto.conf"
cp netcalc6.lua "$base/usr/lib/wan-ip-pool-auto/"
cat > "$base/mock-bin/mock" <<'MOCK'
#!/bin/sh
case "$(basename "$0")" in
 logger) printf '%s\n' "$*" >> "$AWP6_BASE/log";;
 ubus)
    [ "${AWP6_DOWN:-0}" != 1 ] || exit 1
    case "$2" in
     *.wan6) echo '{"up":true,"l3_device":"eth2","ipv6-address":[{"address":"2001:db8:1:2::1","mask":64,"preferred":3600}],"route":[{"target":"::","mask":0,"nexthop":"fe80::1"}]}' ;;
     *) echo '{"up":true,"l3_device":"br-lan","ipv6-prefix-assignment":[{"address":"fd12:3456:789a::","mask":60}]}' ;;
    esac;;
 ip)
    printf '%s\n' "$*" >> "$AWP6_BASE/ip-calls"
    case "$*" in
     '-6 rule show '*)
       if [ "${AWP6_BUSY:-0}" = 1 ];then echo '32000: foreign rule';
       elif [ -f "$AWP6_BASE/return-rule" ];then echo '32000: from all to 2001:db8:1:2::/64 iif eth2 lookup 40960';fi;;
     '-6 rule add '*) touch "$AWP6_BASE/return-rule";;
     '-6 rule del '*) rm -f "$AWP6_BASE/return-rule";;
     '-6 route show table '*) [ ! -f "$AWP6_BASE/return-route" ] || echo '2001:db8:1:2::/64 dev br-lan metric 4096';;
     '-6 route replace '*) touch "$AWP6_BASE/return-route";;
     '-6 route del '*table*) rm -f "$AWP6_BASE/return-route";;
     '-6 addr add '*) echo "$4" >> "$AWP6_BASE/aliases";;
     '-6 addr del '*) grep -vxF "$4" "$AWP6_BASE/aliases" > "$AWP6_BASE/next" || :;mv "$AWP6_BASE/next" "$AWP6_BASE/aliases";;
     '-o -6 addr show '* )
       echo '2: eth2 inet6 2001:db8:1:2::1/64 scope global'
       i=0
       if [ -f "$AWP6_BASE/aliases" ];then
        while read -r addr;do i=$((i+1));if [ "$i" -eq 1 ] && [ ! -f "$AWP6_BASE/dad-done" ];then echo "2: eth2 inet6 $addr dadfailed";else echo "2: eth2 inet6 $addr scope global";fi;done < "$AWP6_BASE/aliases"
       fi;;
     '-6 route show '*) [ ! -f "$AWP6_BASE/route" ] || echo 'default via fe80::1 dev eth2 metric 4096';;
     '-6 route add '*) touch "$AWP6_BASE/route";;
     '-6 route del '*) rm -f "$AWP6_BASE/route";;
    esac;;
 nft)
    case "$*" in
     'list chain '*) exit 1;;
     'list table ip6 awp6_auto') test -f "$AWP6_BASE/nat";;
     'delete table ip6 awp6_auto') rm -f "$AWP6_BASE/nat";;
     '-f '*) case "$2" in */rules.nft) touch "$AWP6_BASE/nat";touch "$AWP6_BASE/dad-done";; esac;;
    esac;;
 curl)
    [ "${AWP6_FAIL:-0}" != 1 ] || exit 1
    case "$*" in *'%{remote_ip}'*) echo '2409:8c54::1';exit 0;; esac
    case "$*" in *'--connect-to ::[2409:8c54:0000:0000:0000:0000:0000:0001]:'*) :;; *) exit 1;; esac
    bad=$(sed -n '2s|/128$||p' "$AWP6_BASE/aliases")
    case "$*" in *"--interface $bad "*) echo 'mock TLS failed' >&2;exit 1;; esac;;
 sleep) :;;
esac
MOCK
chmod 700 "$base/mock-bin/mock"
for name in logger ubus ip nft curl sleep;do ln -s mock "$base/mock-bin/$name";done
PATH="$base/mock-bin:/usr/sbin:/usr/bin:/sbin:/bin";export PATH
for name in logger ubus ip nft curl sleep;do test "$(command -v "$name")" = "$base/mock-bin/$name";done
grep -qF '[ -z "$BASE" ] || PATH="$BASE/mock-bin:$PATH"' ./wan-ipv6-pool-auto
sh ./wan-ipv6-pool-auto refresh > "$base/stdout"
grep -q '可验证=3，冲突或未就绪=1' "$base/stdout"
! grep -q '进度\|IPv6 验证失败' "$base/log"
test "$(wc -l < "$base/tmp/wan-ipv6-pool-auto/pool")" -eq 2
test "$(wc -l < "$base/aliases")" -eq 2
test -f "$base/route"
test -f "$base/return-route";test -f "$base/return-rule"
grep -qF 'rule add priority 32000 iif eth2 to 2001:0db8:0001:0002:0000:0000:0000:0000/64 lookup 40960' "$base/ip-calls"
before=$(sha256sum "$base/tmp/wan-ipv6-pool-auto/pool")
logs=$(wc -l < "$base/log")
sh ./wan-ipv6-pool-auto check >> "$base/stdout"
test "$before" = "$(sha256sum "$base/tmp/wan-ipv6-pool-auto/pool")"
test "$logs" -eq "$(wc -l < "$base/log")"
rm "$base/nat" "$base/route" "$base/return-route" "$base/return-rule"
sh ./wan-ipv6-pool-auto check >> "$base/stdout"
test -f "$base/nat";test -f "$base/route"
test -f "$base/return-route";test -f "$base/return-rule"
grep -q '路由已恢复' "$base/log"
AWP6_FAIL=1 sh ./wan-ipv6-pool-auto refresh >> "$base/stdout" 2>&1 && exit 1
test ! -s "$base/aliases"
test ! -f "$base/route";test ! -f "$base/nat"
test ! -f "$base/return-route";test ! -f "$base/return-rule"
logs=$(wc -l < "$base/log")
sh ./wan-ipv6-pool-auto check >> "$base/stdout"
test "$logs" -eq "$(wc -l < "$base/log")"
AWP6_BUSY=1 sh ./wan-ipv6-pool-auto refresh >> "$base/stdout" 2>&1 && exit 1
grep -q '已被占用' "$base/log"
test ! -s "$base/aliases";test ! -f "$base/route"
test ! -f "$base/tmp/wan-ipv6-pool-auto/return-route-owned"
AWP6_DOWN=1 sh ./wan-ipv6-pool-auto check >> "$base/stdout"
logs=$(wc -l < "$base/log")
AWP6_DOWN=1 sh ./wan-ipv6-pool-auto check >> "$base/stdout"
test "$logs" -eq "$(wc -l < "$base/log")"
test "$(grep -c 'WAN 未就绪' "$base/log")" -eq 1
echo 'ipv6 pool: DAD/probe failures/healthy check/NAT+route recovery/rollback/retry checks passed'
