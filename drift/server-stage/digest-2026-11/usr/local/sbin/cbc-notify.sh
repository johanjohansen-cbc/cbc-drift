#!/bin/bash
# CBC daglig digest 2026-11-06: faelles afsender for alle CBC-serverscripts.
#
# Brug:  <body paa stdin> | cbc-notify.sh <digest|alert> "<emne>" [<job-navn>]
#   alert  -> sendes STRAKS til johan@cbcit.dk, From "CBC Drift <noreply@cbcit.dk>", emne-praefiks "[CBC ALARM] ".
#   digest -> gemmes i /var/spool/cbc-digest/inbox/YYYYMMDD-HHMMSS_<job>.txt (1. linje = emne, derefter body)
#             og kommer med i naeste daglige digest-mail (cbc-digest.sh, 07:30).
#
# Rollback-kontakt: env CBC_NOTIFY_PASSTHROUGH=1 ELLER filen /etc/cbc-digest.disabled -> alt sendes straks
#                   (digest-beskeder uden ALARM-praefiks), praecis som foer digesten.
# Fejlsikker: kan spoolen ikke skrives, sendes beskeden straks i stedet. Log: /var/log/cbc-digest.log
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C.UTF-8

MODE=${1:-}; SUBJ=${2:-}; JOB=${3:-misc}
TO=${CBC_NOTIFY_TO:-johan@cbcit.dk}
FROM_ADDR=noreply@cbcit.dk
FROM_NAME="CBC Drift"
SPOOL=/var/spool/cbc-digest/inbox
LOG=/var/log/cbc-digest.log

case "$MODE" in digest|alert) ;; *) echo "brug: $0 <digest|alert> \"<emne>\" [<job>]  (body paa stdin)" >&2; exit 2;; esac
[ -n "$SUBJ" ] || SUBJ="(intet emne)"
JOB=$(printf '%s' "$JOB" | tr -c 'A-Za-z0-9_.-' '_' | cut -c1-40)

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '%s [%s] %s\n' "$(ts)" "$JOB" "$*" >> "$LOG" 2>/dev/null; }

BODY=$(cat)

# RFC 2047-indkodning af emnet (aeoeaa i emner), i bidder af 45 bytes saa ingen header-linje bliver for lang
enc_subject() {
  local s=$1 out="" chunk
  if ! printf '%s' "$s" | LC_ALL=C grep -q '[^ -~]'; then printf '%s' "$s"; return; fi
  while [ -n "$s" ]; do
    chunk=$(printf '%s' "$s" | LC_ALL=C.UTF-8 cut -c1-30)
    s=${s:${#chunk}}
    out+="${out:+$'\n '}=?UTF-8?B?$(printf '%s' "$chunk" | base64 -w0)?="
  done
  printf '%s' "$out"
}

send_now() { # $1 = endeligt emne
  {
    printf 'From: %s <%s>\nTo: %s\nSubject: %s\nMIME-Version: 1.0\nContent-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: 8bit\nX-CBC-Job: %s\n\n' \
      "$FROM_NAME" "$FROM_ADDR" "$TO" "$(enc_subject "$1")" "$JOB"
    printf '%s\n' "$BODY"
  } | /usr/sbin/sendmail -i -f "$FROM_ADDR" -t
}

PASS=0
{ [ "${CBC_NOTIFY_PASSTHROUGH:-0}" = 1 ] || [ -e /etc/cbc-digest.disabled ]; } && PASS=1

if [ "$MODE" = alert ]; then
  send_now "[CBC ALARM] $SUBJ"; rc=$?
  log "alert sendt (rc=$rc): $SUBJ"; exit $rc
fi

if [ "$PASS" = 1 ]; then
  send_now "$SUBJ"; rc=$?
  log "digest->passthrough sendt straks (rc=$rc): $SUBJ"; exit $rc
fi

F="$SPOOL/$(date +%Y%m%d-%H%M%S)_$JOB.txt"
[ -e "$F" ] && F="${F%.txt}_$$.txt"
if ( umask 077; printf '%s\n%s\n' "$SUBJ" "$BODY" > "$F" ) 2>/dev/null; then
  log "digest spoolet: $(basename "$F"): $SUBJ"; exit 0
fi
send_now "$SUBJ (digest-spool utilgaengelig - sendt straks)"; rc=$?
log "FEJL: kunne ikke skrive $F - sendt straks (rc=$rc): $SUBJ"; exit $rc
