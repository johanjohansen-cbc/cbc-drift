#!/bin/bash
# TRIN 2c — netvaerks-range-saet (Google/Meta) til web_egress. Filteret forbliver i log-only.
set -uo pipefail
H=/root/cbc-hardening-2026-10; ST=$H/stage; B=$H/backup
say(){ printf '\n== %s\n' "$*"; }
fail(){ echo "FEJL: $*"; exit 1; }

say "0. backup af nuvaerende boot-fil + refresh-script"
cp -a /etc/nftables.d/cbc_fw.nft $B/cbc_fw.nft.pre-ranges
cp -a /usr/local/sbin/cbc-web-egress-refresh.sh $B/cbc-web-egress-refresh.sh.pre-ranges

say "1. syntaks-check af ny boot-fil"
nft -c -f $ST/etc/nftables.d/cbc_fw.nft || fail "ny cbc_fw.nft fejler nft -c"

say "2. live: tilfoej saet + to accept-regler FOER taelleren (ingen tabel-genskabelse)"
nft add set inet cbc_fw web_allow_net4 '{ type ipv4_addr; flags interval; auto-merge; }' || fail "add set net4"
nft add set inet cbc_fw web_allow_net6 '{ type ipv6_addr; flags interval; auto-merge; }' || fail "add set net6"
CNT=$(nft -a list chain inet cbc_fw web_egress | grep 'cbc-egress-hits' | grep -oE 'handle [0-9]+' | awk '{print $2}')
[ -n "$CNT" ] || fail "fandt ikke taeller-reglen"
nft insert rule inet cbc_fw web_egress handle "$CNT" ip daddr @web_allow_net4 tcp dport '{ 443, 587 }' accept || fail "insert net4-regel"
nft insert rule inet cbc_fw web_egress handle "$CNT" ip6 daddr @web_allow_net6 tcp dport '{ 443, 587 }' accept || fail "insert net6-regel"
nft list chain inet cbc_fw web_egress

say "3. installer filer (boot-fil, refresh, ranges-fetch, timer)"
install -m 644 $ST/etc/nftables.d/cbc_fw.nft /etc/nftables.d/cbc_fw.nft
install -m 750 $ST/usr/local/sbin/cbc-web-egress-refresh.sh      /usr/local/sbin/
install -m 750 $ST/usr/local/sbin/cbc-web-egress-ranges-fetch.sh /usr/local/sbin/
install -m 644 $ST/etc/systemd/system/cbc-web-egress-ranges.service /etc/systemd/system/
install -m 644 $ST/etc/systemd/system/cbc-web-egress-ranges.timer   /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now cbc-web-egress-ranges.timer
nft -c -f /etc/nftables.d/cbc_fw.nft && echo boot-fil-OK

say "4. hent ranges (goog.json + AS32934) -> ranges-fil -> refresh"
/usr/local/sbin/cbc-web-egress-ranges-fetch.sh || echo "ADVARSEL: ranges-fetch fejlede — se /var/log/cbc-web-egress-refresh.log"
tail -3 /var/log/cbc-web-egress-refresh.log
head -8 /etc/cbc-web-egress-ranges.txt
echo "ranges i fil: $(grep -vc '^#' /etc/cbc-web-egress-ranges.txt)"
echo "elements-fil (boot): $(wc -l < /etc/nftables.d/cbc_web_egress_elements.nft) linjer"
nft -c -f /etc/nftables.d/cbc_web_egress_elements.nft && echo elements-fil-OK

say "5. er de to loggede IP'er nu daekket?"
for ip in 2a03:2880:f084:105:face:b00c::3 2a00:1450:4001:c1f::8d 2a00:1450:4001:c25::8d; do
  printf '%s -> ' "$ip"; nft get element inet cbc_fw web_allow_net6 "{ $ip }" >/dev/null 2>&1 && echo "daekket (net6)" || echo "IKKE daekket"
done
for ip in 142.251.110.141 157.240.1.1; do
  printf '%s -> ' "$ip"; nft get element inet cbc_fw web_allow_net4 "{ $ip }" >/dev/null 2>&1 && echo "daekket (net4)" || echo "IKKE daekket"
done

say "6. test som datagaardendk (maa ikke give nye log-linjer)"
before=$(journalctl -k --since "-1 min" | grep -c cbc-egress-drop || true)
su -s /bin/bash datagaardendk -c 'curl -sS -o /dev/null --max-time 15 -w "graph.facebook.com %{http_code}\n" https://graph.facebook.com/; curl -sS -o /dev/null --max-time 15 -w "sitekit.withgoogle.com %{http_code}\n" https://sitekit.withgoogle.com/; curl -sS -o /dev/null --max-time 15 -w "www.googleapis.com %{http_code}\n" https://www.googleapis.com/'
sleep 1
after=$(journalctl -k --since "-1 min" | grep -c cbc-egress-drop || true)
echo "nye log-linjer: $((after-before)) (forventet 0)"
/usr/local/sbin/cbc-web-egress-mode.sh status | head -2
echo
echo ">>> Rollback 2c: cp -a $B/cbc_fw.nft.pre-ranges /etc/nftables.d/cbc_fw.nft; cp -a $B/cbc-web-egress-refresh.sh.pre-ranges /usr/local/sbin/cbc-web-egress-refresh.sh; systemctl disable --now cbc-web-egress-ranges.timer; /usr/local/sbin/cbc-fw-apply.sh; /usr/local/sbin/cbc-web-egress-refresh.sh"
