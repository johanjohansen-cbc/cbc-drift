#!/bin/bash
# CBC daglig digest 2026-11-06: modtager mails sendt til digest@server.cbcit.dk (Postfix-alias i /etc/aliases:
#   digest: "|/usr/local/sbin/cbc-digest-ingest.sh"
# Koerer som Postfix' default_privs-bruger (nobody:nogroup) med beskeden paa stdin.
# Selve parsingen (MIME, emne-dekodning, tekstdel, alarm-moenstre) ligger i /usr/local/lib/cbc-digest/ingest.php.
#
# nobody maa IKKE sende mail (Plesk limit-out afviser systembrugere). Alarmer lægges derfor i
# /var/spool/cbc-digest/outbox, som root-servicen cbc-digest-alert (systemd path-unit) sender straks.
# Fejlsikker: fejler PHP-parseren, lægges den RAA besked i outbox som alarm. Kan heller ikke det skrives,
# returneres 75 (EX_TEMPFAIL) -> Postfix proever igen senere i stedet for at bounce.
# Log: syslog (tag cbc-digest-ingest) - nobody kan ikke skrive i /var/log.
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C.UTF-8 TZ=Europe/Copenhagen
PHP=/opt/plesk/php/8.4/bin/php
LIB=/usr/local/lib/cbc-digest/ingest.php
OUTBOX=/var/spool/cbc-digest/outbox
MAXBYTES=5242880

TMP=$(mktemp /tmp/cbc-digest-ingest.XXXXXX) || { logger -t cbc-digest-ingest "mktemp fejlede - beskeden udskydes (75)"; exit 75; }
trap 'rm -f "$TMP"' EXIT
head -c "$MAXBYTES" > "$TMP"
cat > /dev/null   # resten (> 5 MB) kasseres

"$PHP" -d memory_limit=256M -d display_errors=stderr "$LIB" "$TMP" 2> >(logger -t cbc-digest-ingest)
rc=$?
[ "$rc" = 0 ] && exit 0

logger -t cbc-digest-ingest "ingest.php rc=$rc - lægger raa besked i outbox som alarm"
F="$OUTBOX/$(date +%Y%m%d-%H%M%S)_ingest-fejl_$$.msg"
if ( umask 077; set -o noclobber
     { printf 'alert\ndigest-ingest kunne ikke behandle en besked (rc=%s)\n' "$rc"
       printf 'cbc-digest-ingest.sh kunne ikke parse/gemme en mail til digest@server.cbcit.dk. Den raa besked (max 200 KB) foelger:\n\n'
       head -c 200000 "$TMP"; } > "$F" ) 2>/dev/null; then
  exit 0
fi
logger -t cbc-digest-ingest "kunne heller ikke skrive $F - Postfix udskyder beskeden (75)"
exit 75
