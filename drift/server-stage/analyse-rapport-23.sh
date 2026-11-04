#!/bin/bash
# Analyse af egress-drop-linjer efter trin 2d (22/10 12:22) — rDNS + DNS-log-korrelation + rapportmail-status
set -uo pipefail
L=/root/cbc-hardening-2026-10/dns-queries.log
say(){ printf '\n== %s\n' "$*"; }

say "A. rDNS for ukendte destinationer"
for ip in 2401:1d80:32fe:0:600:d9:4:9d02 2606:4700:3034::6815:3089 2606:4700:3037::ac43:9827; do
  printf '%s -> %s\n' "$ip" "$(dig +short -x "$ip" @127.0.0.53 2>/dev/null | tr '\n' ' ')"
done

say "B. DNS-opslag i vinduerne (+-5 s)"
for w in "14:07:0" "14:07:1" "21:00:0" "21:00:1" "04:01:0" "04:01:1"; do
  echo "-- $w"; grep -E "(^| )[0-9:.]*$w" "$L" 2>/dev/null | grep -oE 'A\?? [^ ]+|AAAA\?? [^ ]+|[A-Za-z0-9.-]+\.(com|net|org|dk|io|co)\.' | sort | uniq -c | sort -rn | head -12
done

say "B2. raa DNS-loglinjer 21:00:00-21:00:15 (22/10)"
grep -E '^[^ ]*21:00:(0|1)[0-9]' "$L" | head -30

say "B3. raa DNS-loglinjer 04:01:0x (23/10) og 14:07:1x (22/10)"
grep -E '^[^ ]*04:01:(0|1)[0-9]' "$L" | head -15
grep -E '^[^ ]*14:07:(0|1)[0-9]' "$L" | head -15

say "C. rapport-cron + mail 06:55"
grep -h cbc-egress-report /var/log/syslog 2>/dev/null | tail -3
journalctl -u cron --since "2026-10-23 06:50" --until "2026-10-23 07:05" --no-pager | grep -i egress
journalctl -t postfix/smtp -t postfix/cleanup -t postfix/qmgr --since "2026-10-23 06:50" --until "2026-10-23 07:05" --no-pager | tail -8

say "D. IPv6-adresser for wordpress.org/public-api.wordpress.com/api.wordpress.org (AAAA)"
for h in api.wordpress.org downloads.wordpress.org public-api.wordpress.com wordpress.org planet.wordpress.org woocommerce.com; do
  printf '%s AAAA: %s\n' "$h" "$(dig +short AAAA "$h" @127.0.0.53 | tr '\n' ' ')"
done

say "E. 2401:1d80 whois-org"
whois 2401:1d80:32fe:0:600:d9:4:9d02 2>/dev/null | grep -iE '^(netname|descr|org-name|OrgName|owner)' | head -5
