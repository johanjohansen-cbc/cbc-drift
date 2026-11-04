#!/bin/bash
# TRIN 2b — efter groen verifikation: timer, DNS-opslagslog, daglig rapport, testmail.
set -uo pipefail
H=/root/cbc-hardening-2026-10; ST=$H/stage
say(){ printf '\n== %s\n' "$*"; }

say "dead-man status (skal vaere stoppet/ikke-eksisterende)"
systemctl is-active cbc-fw-deadman.timer 2>&1 || true

say "1. time-refresh af allowlisten"
systemctl enable --now cbc-web-egress-refresh.timer
systemctl list-timers --no-pager | grep cbc-web-egress

say "2. DNS-opslagslog (tcpdump paa lo -> $H/dns-queries.log) i log-only-vinduet"
systemctl is-active cbc-dns-capture 2>/dev/null && systemctl stop cbc-dns-capture
systemd-run --unit=cbc-dns-capture --description="CBC DNS query capture (egress log-only window)" \
  -p StandardOutput=append:$H/dns-queries.log -p StandardError=null \
  /usr/bin/tcpdump -i lo -nn -l -tttt 'udp dst port 53'
sleep 2; systemctl is-active cbc-dns-capture

say "3. daglig rapport 06:55 -> johan@cbcit.dk"
install -m 644 $ST/etc/cron.d/cbc-egress-report /etc/cron.d/cbc-egress-report
echo "-- testrapport (sidste 2 timer) sendes nu:"
/usr/local/sbin/cbc-egress-report.sh "-2 hours" && echo rapport-sendt
sleep 3
journalctl --since "-1 min" -t postfix/smtp 2>/dev/null | grep -oE 'to=<[^>]+>.*status=[a-z]+' | tail -2

say "4. cbc-fw.service reload-sti (boot-aekvivalent) — bevidst IKKE koert; tabellen er live og boot-filen verificeret"
systemctl is-enabled cbc-fw
/usr/local/sbin/cbc-web-egress-mode.sh status
