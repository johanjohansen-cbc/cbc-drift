#!/bin/bash
# CBC daglig digest 2026-11-06: sender beskeder fra /var/spool/cbc-digest/outbox STRAKS (som root).
# Udloeses af cbc-digest-alert.path (DirectoryNotEmpty) naar cbc-digest-ingest.sh (nobody) har lagt en fil der.
# Filformat: linje 1 = alert|plain, linje 2 = emne, resten = body.
#   alert -> cbc-notify.sh alert   ("[CBC ALARM] <emne>")
#   plain -> sendes straks uden praefiks (bruges naar /etc/cbc-digest.disabled findes)
# Sendt fil slettes; fejlet afsendelse flyttes til outbox/failed/ og logges (kommer med i digesten via loggen).
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C.UTF-8
OUTBOX=/var/spool/cbc-digest/outbox
LOG=/var/log/cbc-digest.log
log() { printf '%s [digest-alert] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

shopt -s nullglob
for f in "$OUTBOX"/*.msg; do
  mode=$(head -n1 "$f"); subj=$(sed -n 2p "$f" | cut -c1-200)
  case "$mode" in
    plain) tail -n +3 "$f" | CBC_NOTIFY_PASSTHROUGH=1 /usr/local/sbin/cbc-notify.sh digest "$subj" digest-ingest; rc=$? ;;
    *)     tail -n +3 "$f" | /usr/local/sbin/cbc-notify.sh alert "$subj" digest-ingest; rc=$? ;;
  esac
  if [ "$rc" = 0 ]; then rm -f -- "$f"; log "sendt ($mode): $subj"
  else mkdir -p "$OUTBOX/failed" && mv -f -- "$f" "$OUTBOX/failed/"; log "FEJL rc=$rc ($mode) - flyttet til $OUTBOX/failed: $subj"; fi
done
exit 0
