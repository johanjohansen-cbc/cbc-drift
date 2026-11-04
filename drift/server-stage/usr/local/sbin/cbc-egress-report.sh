#!/bin/bash
# CBC blast-radius 2026-10-22 — daglig opsummering af web-egress-hits (cbc-egress-drop) til Johan.
# Koeres af /etc/cron.d/cbc-egress-report. Sender ALTID (ogsaa ved 0 hits) saa fravaer = fejl.
# Brug: cbc-egress-report.sh ["-24 hours"]   (valgfrit journalctl --since-udtryk)
set -uo pipefail
TO=johan@cbcit.dk
SINCE=${1:--24 hours}
DNSLOG=/root/cbc-hardening-2026-10/dns-queries.log
MODE=$(nft -a list chain inet cbc_fw web_egress 2>/dev/null | grep -oE 'cbc-egress-mode: [a-z-]+' | awk '{print $2}')
RAW=$(journalctl -k --since "$SINCE" -o short-iso 2>/dev/null | grep 'cbc-egress-drop:')
N=$(printf '%s' "$RAW" | grep -c . || true)

uidname(){ case "$1" in 10000) echo event;; 10001) echo cbcit;; 10002) echo datagaarden;; *) echo "uid$1";; esac; }

BODY="Web-egress-filter (table inet cbc_fw, chain web_egress) — tilstand: ${MODE:-UKENDT}
Vindue: journalctl -k --since '$SINCE' | grep cbc-egress-drop
Hits (pakker, inkl. SYN-gentagelser): $N
"
if [ "$MODE" = log-only ]; then
  BODY+="NB: log-only = trafikken blev TILLADT; listen viser hvad enforce ville have droppet.
"
fi
if [ "$N" -gt 0 ]; then
  AGG=$(printf '%s\n' "$RAW" | sed -nE 's/^([0-9T:+-]+) .*DST=([0-9a-f.:]+) .*PROTO=([A-Z0-9]+) .*DPT=([0-9]+) .*UID=([0-9]+) .*/\5 \2 \3 \4 \1/p')
  BODY+="
Site        Dest-IP                                  Proto Port   Pakker  Foerst/sidst       Reverse-DNS | DNS-opslag lige inden (kandidater)
"
  while read -r uid dst proto dpt cnt first last; do
    [ -n "${uid:-}" ] || continue
    rdns=$(dig +short +time=2 +tries=1 -x "$dst" 2>/dev/null | head -1)
    names=""
    if [ -r "$DNSLOG" ]; then
      t0=$(date -d "$first" +%s 2>/dev/null || echo 0)
      if [ "$t0" -gt 0 ]; then
        for off in 3 2 1 0; do
          ts=$(date -d "@$((t0-off))" '+%Y-%m-%d %H:%M:%S')
          names+=$(grep -F "$ts" "$DNSLOG" 2>/dev/null | grep -oE ' (A|AAAA)\? [^ ]+' | awk '{print $2}' | sed 's/\.$//' | sort -u | tr '\n' ' ')
        done
      fi
    fi
    printf -v row '%-11s %-40s %-5s %-6s %-7s %s/%s  %s | %s\n' "$(uidname "$uid")" "$dst" "$proto" "$dpt" "$cnt" "${first:11:8}" "${last:11:8}" "${rdns:--}" "${names:--}"
    BODY+="$row"
  done < <(printf '%s\n' "$AGG" | awk '{k=$1" "$2" "$3" "$4; c[k]++; if(!(k in f)) f[k]=$5; l[k]=$5} END{for(k in c) print k, c[k], f[k], l[k]}' | sort -k1,1 -k5,5nr)
fi
BODY+="

Allowlist: /etc/cbc-web-egress-hosts.txt — tilfoej host, koer: systemctl start cbc-web-egress-refresh.service
Skift tilstand: /usr/local/sbin/cbc-web-egress-mode.sh enforce|log-only|status
Runbook: /root/cbc-hardening-2026-10/README.md"
printf 'To: %s\nSubject: [CBC] web-egress-rapport (%s): %s hits\nContent-Type: text/plain; charset=UTF-8\n\n%s\n' "$TO" "${MODE:-?}" "$N" "$BODY" | /usr/sbin/sendmail -t
