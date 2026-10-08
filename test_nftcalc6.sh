#!/bin/sh
set -eu
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' 2001:db8:1:2::1234 2001:db8:1:2::5678 > "$tmp/pool"
lua netcalc6.lua pool "$tmp/pool" eth2 fd12:3456:789a:0000:0000:0000:0000:0000/60 2001:0db8:0001:0002:0000:0000:0000:0000/64 br-lan | sed 's/awp6_auto/awp6_test_auto/g' > "$tmp/pool.nft"
nft -c -f "$tmp/pool.nft"
lua netcalc6.lua probe "$tmp/pool" eth2 | sed 's/awp6_probe/awp6_test_probe/g' > "$tmp/probe.nft"
nft -c -f "$tmp/probe.nft"
echo 'nftcalc6: NAT66 and same-source probe kernel checks passed'
