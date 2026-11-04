#!/bin/bash
# TRIN 2f (23/10) — TCP 80 til hostlistens vaerter (web_allow4/6), ikke ranges. Johan "Go paa dette".
set -uo pipefail
H=/root/cbc-hardening-2026-10; ST=$H/stage; B=$H/backup
say(){ printf '\n== %s\n' "$*"; }
fail(){ echo "FEJL: $*"; exit 1; }

say "0. backup + syntaks"
cp -a /etc/nftables.d/cbc_fw.nft $B/cbc_fw.nft.pre-port80
nft -c -f $ST/etc/nftables.d/cbc_fw.nft || fail "ny boot-fil fejler nft -c"

say "1. live: erstat de to host-set-regler"
for fam in "ip daddr @web_allow4" "ip6 daddr @web_allow6"; do
  HND=$(nft -a list chain inet cbc_fw web_egress | grep -F "$fam tcp dport { 443, 587 } accept" | grep -oE 'handle [0-9]+' | awk '{print $2}')
  [ -n "$HND" ] || fail "fandt ikke regel: $fam"
  nft replace rule inet cbc_fw web_egress handle "$HND" $fam tcp dport { 80, 443, 587 } accept || fail "replace $fam"
  echo "erstattet: $fam (handle $HND)"
done
install -m 644 $ST/etc/nftables.d/cbc_fw.nft /etc/nftables.d/cbc_fw.nft
nft -c -f /etc/nftables.d/cbc_fw.nft && echo boot-fil-OK
nft list chain inet cbc_fw web_egress | grep -E 'web_allow|cbc-egress-mode'

say "2. test som datagaardendk"
b=$(journalctl -k --since '-1 min' | grep -c cbc-egress-drop)
su -s /bin/bash datagaardendk -c 'curl -sS -o /dev/null --max-time 10 -w "http://www.datagaarden.dk -> %{http_code} (redirect til %{redirect_url})\n" http://www.datagaarden.dk/ 2>&1'
su -s /bin/bash datagaardendk -c 'curl -sS -o /dev/null --max-time 10 -w "http://api.wordpress.org -> %{http_code}\n" http://api.wordpress.org/ 2>&1'
su -s /bin/bash datagaardendk -c 'curl -sS -o /dev/null --max-time 6 -w "BLOKERET http://example.com -> %{http_code}\n" http://example.com/ 2>&1 | tail -1'
sleep 1
a=$(journalctl -k --since '-1 min' | grep -c cbc-egress-drop)
echo "nye log-linjer (forventet: kun example.com): $((a-b))"
journalctl -k --since '-1 min' | grep cbc-egress-drop | grep -oE 'DST=[^ ]+ .*DPT=[^ ]+ .*UID=[0-9]+' | sed -E 's/LEN.*DPT/DPT/; s/WINDOW.*UID/UID/' | sort | uniq -c
/usr/local/sbin/cbc-web-egress-mode.sh status | head -1
