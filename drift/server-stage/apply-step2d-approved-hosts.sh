#!/bin/bash
# TRIN 2d — Johans godkendte vaerter (A–E, H, Complianz) + UDP 123-regel for web-uids. Stadig log-only.
set -uo pipefail
H=/root/cbc-hardening-2026-10; ST=$H/stage; B=$H/backup
say(){ printf '\n== %s\n' "$*"; }
fail(){ echo "FEJL: $*"; exit 1; }

say "0. backup"
cp -a /etc/cbc-web-egress-hosts.txt $B/cbc-web-egress-hosts.txt.pre-approved
cp -a /etc/nftables.d/cbc_fw.nft $B/cbc_fw.nft.pre-ntp

say "1. hostliste"
install -m 644 $ST/etc/cbc-web-egress-hosts.txt /etc/cbc-web-egress-hosts.txt
echo "aktive hosts: $(grep -vcE '^\s*#|^\s*$' /etc/cbc-web-egress-hosts.txt)"

say "2. live: UDP 123-regel foer taelleren"
nft -c -f $ST/etc/nftables.d/cbc_fw.nft || fail "ny boot-fil fejler nft -c"
if nft list chain inet cbc_fw web_egress | grep -q '"web-ntp"'; then echo "regel findes allerede"; else
  CNT=$(nft -a list chain inet cbc_fw web_egress | grep 'cbc-egress-hits' | grep -oE 'handle [0-9]+' | awk '{print $2}')
  [ -n "$CNT" ] || fail "fandt ikke taeller-reglen"
  nft insert rule inet cbc_fw web_egress handle "$CNT" udp dport 123 accept comment '"web-ntp"' || fail "insert ntp-regel"
fi
install -m 644 $ST/etc/nftables.d/cbc_fw.nft /etc/nftables.d/cbc_fw.nft
nft -c -f /etc/nftables.d/cbc_fw.nft && echo boot-fil-OK
nft list chain inet cbc_fw web_egress

say "3. refresh (oploes nye hosts)"
/usr/local/sbin/cbc-web-egress-refresh.sh; tail -1 /var/log/cbc-web-egress-refresh.log
grep -E 'WARN' /var/log/cbc-web-egress-refresh.log | tail -5
/usr/local/sbin/cbc-web-egress-mode.sh status | head -2

say "4. test som cbcitdk: godkendte vaerter (forventet 0 nye log-linjer)"
b=$(journalctl -k --since '-1 min' | grep -c cbc-egress-drop)
su -s /bin/bash cbcitdk -c 'for h in noc1.wordfence.com woocommerce.com rest.akismet.com us9.api.mailchimp.com www.wpdesk.net api.uxthemes.com plugin-updates.wp-migration.com complianz.io wordpress.org; do curl -sS -o /dev/null --max-time 15 -w "$h %{http_code}\n" "https://$h/"; done'
sleep 1
a=$(journalctl -k --since '-1 min' | grep -c cbc-egress-drop)
echo "nye log-linjer: $((a-b))"
journalctl -k --since '-1 min' | grep cbc-egress-drop | grep -oE 'DST=[^ ]+ .*DPT=[^ ]+' | sed -E 's/LEN.*DPT/DPT/' | sort -u
