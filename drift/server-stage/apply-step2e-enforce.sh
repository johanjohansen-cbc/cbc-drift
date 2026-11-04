#!/bin/bash
# TRIN 2e (23/10) — license.wpdesk.dev paa listen + FLIP TIL ENFORCE med dead-man (5 min -> log-only).
# Efter groen verifikation: systemctl stop cbc-fw-deadman.timer
set -uo pipefail
H=/root/cbc-hardening-2026-10; ST=$H/stage; B=$H/backup
WP="/opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp"
say(){ printf '\n== %s\n' "$*"; }
fail(){ echo "FEJL: $*"; exit 1; }

say "0. backup"
cp -a /etc/cbc-web-egress-hosts.txt $B/cbc-web-egress-hosts.txt.pre-enforce
cp -a /etc/nftables.d/cbc_fw.nft $B/cbc_fw.nft.pre-enforce

say "1. hostliste + refresh"
install -m 644 $ST/etc/cbc-web-egress-hosts.txt /etc/cbc-web-egress-hosts.txt
echo "aktive hosts: $(grep -vcE '^\s*#|^\s*$' /etc/cbc-web-egress-hosts.txt)"
/usr/local/sbin/cbc-web-egress-refresh.sh; tail -1 /var/log/cbc-web-egress-refresh.log
for ip in 2606:4700:3037::ac43:9827 2606:4700:3034::6815:3089; do
  nft get element inet cbc_fw web_allow6 "{ $ip }" >/dev/null 2>&1 && echo "v6 OK: $ip" || fail "mangler i web_allow6: $ip"
done
for ip in 172.67.152.39 104.21.48.137; do
  nft get element inet cbc_fw web_allow4 "{ $ip }" >/dev/null 2>&1 && echo "v4 OK: $ip" || fail "mangler i web_allow4: $ip"
done

say "2. dead-man (5 min -> log-only)"
systemctl stop cbc-fw-deadman.timer 2>/dev/null || true
systemd-run --on-active=300 --unit=cbc-fw-deadman --description="CBC egress dead-man -> log-only" \
  /bin/sh -c "/usr/local/sbin/cbc-web-egress-mode.sh log-only; logger -t cbc-fw-deadman 'ROLLBACK til log-only udfoert'" || fail "dead-man"

say "3. ENFORCE"
/usr/local/sbin/cbc-web-egress-mode.sh enforce || fail "mode enforce"
/usr/local/sbin/cbc-web-egress-mode.sh status | head -2
nft list chain inet cbc_fw web_egress | grep -E 'cbc-egress-mode'
grep -E 'cbc-egress-mode' /etc/nftables.d/cbc_fw.nft
nft -c -f /etc/nftables.d/cbc_fw.nft && echo boot-fil-OK

say "4. test som web-uids"
b=$(journalctl -k --since '-1 min' | grep -c cbc-egress-drop)
for pair in cbcitdk:cbcit.dk datagaardendk:datagaarden.dk eventcbcitdk:event.cbcit.dk; do
  u=${pair%%:*}; d=${pair##*:}
  echo "-- $u"
  su -s /bin/bash "$u" -c 'curl -sS -o /dev/null --max-time 10 -w "tilladt woocommerce.com %{http_code}\n" https://woocommerce.com/ 2>&1'
  su -s /bin/bash "$u" -c 'curl -sS -o /dev/null --max-time 10 -w "tilladt api.wordpress.org %{http_code}\n" https://api.wordpress.org/core/version-check/1.7/ 2>&1'
  su -s /bin/bash "$u" -c 'curl -sS -o /dev/null --max-time 10 -w "tilladt www.google.com %{http_code}\n" https://www.google.com/ 2>&1'
  su -s /bin/bash "$u" -c 'curl -sS -o /dev/null --max-time 6 -w "BLOKERET example.com %{http_code}\n" https://example.com/ 2>&1 | tail -1'
done
echo "-- loopback (egen IP via /etc/hosts og CF)"
su -s /bin/bash cbcitdk -c 'curl -sS -o /dev/null --max-time 10 -w "www.cbcit.dk %{http_code}\n" https://www.cbcit.dk/ 2>&1'
su -s /bin/bash eventcbcitdk -c 'curl -sS -o /dev/null --max-time 10 -w "event.cbcit.dk %{http_code}\n" https://event.cbcit.dk/ 2>&1'
su -s /bin/bash datagaardendk -c 'curl -sS -o /dev/null --max-time 10 -w "www.datagaarden.dk %{http_code}\n" https://www.datagaarden.dk/ 2>&1'
echo "-- wp-cli core version"
su -s /bin/bash eventcbcitdk -c "$WP --path=/var/www/vhosts/event.cbcit.dk/httpdocs --skip-themes --skip-plugins core version"
su -s /bin/bash cbcitdk -c "$WP --path=/var/www/vhosts/cbcit.dk/httpdocs --skip-themes --skip-plugins core version"
su -s /bin/bash datagaardendk -c "$WP --path=/var/www/vhosts/datagaarden.dk/httpdocs --skip-themes --skip-plugins core version"
echo "-- mail via Brevo-relay (wp-cli som event-uid, port 587 lokal postfix = lo)"
su -s /bin/bash eventcbcitdk -c "$WP --path=/var/www/vhosts/event.cbcit.dk/httpdocs --skip-themes --skip-plugins eval 'echo wp_mail(\"johan@cbcit.dk\",\"[CBC] egress enforce-test\",\"Sendt fra event-uid efter enforce-flip.\") ? \"wp_mail OK\" : \"wp_mail FEJL\", PHP_EOL;'"
sleep 2
a=$(journalctl -k --since '-1 min' | grep -c cbc-egress-drop)
echo "nye log-linjer (forventet: kun example.com): $((a-b))"
journalctl -k --since '-1 min' | grep cbc-egress-drop | grep -oE 'DST=[^ ]+ .*DPT=[^ ]+ .*UID=[0-9]+' | sed -E 's/LEN.*DPT/DPT/; s/WINDOW.*UID/UID/' | sort | uniq -c

say "5. dead-man status"
systemctl list-timers cbc-fw-deadman.timer --no-pager | head -2
echo ">>> Ved groent: systemctl stop cbc-fw-deadman.timer"
