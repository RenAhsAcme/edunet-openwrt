#!/bin/sh
set -eu
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' 10.25.195.2 10.25.195.3 > "$tmp/pool"
lua nftcalc.lua pool "$tmp/pool" eth2 192.168.10.0/24 10.25.192.0/22 > "$tmp/pool.nft"
grep -q 'priority 99' "$tmp/pool.nft"
grep -q '0 : 10.25.195.2, 1 : 10.25.195.3' "$tmp/pool.nft"
sed 's/awp_auto/awp_test_auto/g' "$tmp/pool.nft" > "$tmp/check-pool.nft"
nft -c -f "$tmp/check-pool.nft"
lua nftcalc.lua probe "$tmp/pool" eth2 > "$tmp/probe.nft"
grep -q 'priority 98' "$tmp/probe.nft"
grep -q 'snat to ip saddr map @sources' "$tmp/probe.nft"
sed 's/awp_probe/awp_test_probe/g' "$tmp/probe.nft" > "$tmp/check-probe.nft"
nft -c -f "$tmp/check-probe.nft"
: > "$tmp/empty"
if lua nftcalc.lua pool "$tmp/empty" eth2 192.168.10.0/24 10.25.192.0/22 2>/dev/null; then exit 1; fi
printf '%s\n' 'bad-address' > "$tmp/bad"
if lua nftcalc.lua probe "$tmp/bad" eth2 2>/dev/null; then exit 1; fi
echo 'nftcalc: pool/probe kernel checks and invalid-input checks passed'
