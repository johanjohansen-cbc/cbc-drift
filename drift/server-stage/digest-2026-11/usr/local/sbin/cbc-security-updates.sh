#!/usr/bin/env bash
# CBC 2026-10-23: hyppig sikkerhedsopdatering (hver 4. time) af Plesk-PHP (plesk-php8*) + Ubuntu-security.
# CBC 2026-10-26: + tredjepart udenfor Plesk-autoupdate (cloudflared, imunify*, alt-php-internal*) - afsnit 2b.
#
# Baggrund: Plesks egen autoupdate koerer KUN i den natlige cron.daily (50plesk-daily ->
#   /opt/psa/admin/bin/autoinstaller --select-product-id plesk --select-release-current --upgrade-installed-components
#   ca. 06:25-06:35), og apt-daily-upgrade (unattended-upgrades) koerer ca. 01:20/02:10. PHP-RCE'en 21/10-2026
#   landede derfor foerst ~14 t efter release. Dette script bringer vinduet ned til <= 4 t for:
#     (1) plesk-php8*-pakker fra Plesks PHP-repoer (PHP84_17/PHP83_17 staar permanent i /etc/apt/sources.list.d/plesk.list)
#     (2) Ubuntu security via unattended-upgrade (samme Allowed-Origins som den natlige koersel)
#   Pakken plesk-php84-fpm genstarter selv FPM i postinst (systemctl condrestart) - verificeret 22/10 i dpkg.log/journal;
#   scriptet tjekker ActiveEnterTimestamp foer/efter og genstarter selv, hvis det ikke skete.
#   plesk-php84-cli's postinst koerer packagemng -sdf (Plesk-registret opdateres); vi koerer desuden php_handler --reread.
#
# Kollisionsvaern: flock paa /run/lock/cbc-security-updates.lock; springer over hvis Plesk-autoinstaller koerer,
#   psa-installer.lock er holdt, eller apt/dpkg-laasen er taget (unattended-upgrades/apt-daily).
#
# Mail til johan@cbcit.dk KUN naar noget faktisk blev opgraderet - eller ved fejl (saa en stille fejl ikke gaar ubemaerket).
# Fuld log: /var/log/cbc-security-updates.log (logrotate: /etc/logrotate.d/cbc-security-updates)
#
# Brug:  cbc-security-updates.sh              normal koersel (cron)
#        cbc-security-updates.sh --test-mail  sender en testmail og stopper
#        cbc-security-updates.sh --dry-run    viser hvad der VILLE blive opgraderet, aendrer intet
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

TO="${TO:-johan@cbcit.dk}"
FROM="cbc-security-updates@server.cbcit.dk"
LOG=/var/log/cbc-security-updates.log
LOCK=/run/lock/cbc-security-updates.lock
FPM_UNIT=plesk-php84-fpm.service
PHP_BIN=/opt/plesk/php/8.4/bin/php
SITES="https://event.cbcit.dk/ https://www.cbcit.dk/ https://www.datagaarden.dk/"   # kanoniske hosts (datagaarden.dk -> 301 www)
HOST=$(hostname -f 2>/dev/null || hostname)

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '%s %s\n' "$(ts)" "$*" >> "$LOG"; }
mail_out() { # $1 = subject; body paa stdin. 2026-11-06: via cbc-notify.sh; $NOTIFY_MODE = digest (default) | alert
  /usr/local/sbin/cbc-notify.sh "${NOTIFY_MODE:-digest}" "$1" security-updates
}

if [ "${1:-}" = "--test-mail" ]; then
  NOTIFY_MODE=alert
  mail_out "[$HOST] cbc-security-updates: testmail" <<EOM
Dette er en testmail fra /usr/local/sbin/cbc-security-updates.sh ($(ts)).
Scriptet koerer hver 4. time (00:45, 04:45, 08:45, 12:45, 16:45, 20:45) og mailer kun, naar pakker faktisk blev opgraderet.
Log: $LOG
EOM
  log "testmail sendt til $TO"
  exit 0
fi
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

touch "$LOG"; chmod 640 "$LOG"
exec 9>"$LOCK"
if ! flock -n 9; then log "SKIP: anden koersel holder $LOCK"; exit 0; fi

# --- kollisionsvaern mod Plesk-autoinstaller og apt/dpkg ---
if pgrep -f '/opt/psa/admin/bin/autoinstaller' >/dev/null; then log "SKIP: Plesk autoinstaller koerer"; exit 0; fi
if [ -e /var/lock/psa-installer.lock ] && ! flock -n /var/lock/psa-installer.lock true 2>/dev/null; then log "SKIP: psa-installer.lock er holdt"; exit 0; fi
if fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock >/dev/null 2>&1; then log "SKIP: apt/dpkg-laas er taget (apt-daily/unattended-upgrades?)"; exit 0; fi

RUN=$(mktemp -d /tmp/cbc-secupd.XXXXXX); trap 'rm -rf "$RUN"' EXIT
ERRORS=()
snapshot() { dpkg-query -W -f='${binary:Package} ${Version}\n' | sort > "$1"; }
snapshot "$RUN/before"
FPM_BEFORE=$(systemctl show -p ActiveEnterTimestampMonotonic --value "$FPM_UNIT")
FPM_BEFORE_H=$(systemctl show -p ActiveEnterTimestamp --value "$FPM_UNIT")
PHPV_BEFORE=$("$PHP_BIN" -r 'echo PHP_VERSION;' 2>/dev/null)

log "START (dry-run=$DRY) php=$PHPV_BEFORE fpm-active-since='$FPM_BEFORE_H'"

# --- 1) apt-get update (alle kilder; Plesk-PHP-repoerne er permanente) ---
if ! apt-get update -qq > "$RUN/aptupd" 2>&1; then
  log "WARN: apt-get update returnerede fejl (fortsaetter med eksisterende lister): $(tr '\n' ' ' < "$RUN/aptupd" | cut -c1-400)"
  ERRORS+=("apt-get update: $(grep -E '^(E|Err)' "$RUN/aptupd" | head -3 | tr '\n' ' ')")
fi

# --- 2) Plesk-PHP: kun pakker fra plesk-php8* der allerede er installeret ---
PHP_PKGS=$(dpkg-query -W -f='${binary:Package}\n' 'plesk-php8*' 2>/dev/null | tr '\n' ' ')
# shellcheck disable=SC2086
PHP_PLAN=$(apt-get -s install --only-upgrade $PHP_PKGS 2>/dev/null | awk '/^Inst plesk-php8/{print $2}' | tr '\n' ' ')
FPM_NOTE="ingen PHP-opgradering"
if [ -n "${PHP_PLAN// /}" ]; then
  log "PHP: opgraderbare pakker: $PHP_PLAN"
  if [ "$DRY" = 1 ]; then
    # shellcheck disable=SC2086
    apt-get -s install --only-upgrade $PHP_PKGS 2>/dev/null | grep -E '^(Inst|Conf) ' | tee -a "$LOG"
  else
    # shellcheck disable=SC2086
    if apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
         install --only-upgrade $PHP_PLAN > "$RUN/aptphp" 2>&1; then
      log "PHP: apt-get install --only-upgrade OK"
    else
      log "ERROR: PHP-opgradering fejlede (rc=$?)"; ERRORS+=("PHP apt-get install fejlede - se log")
    fi
    sed 's/^/    apt| /' "$RUN/aptphp" >> "$LOG"
    if echo " $PHP_PLAN" | grep -q ' plesk-php84'; then
      FPM_AFTER=$(systemctl show -p ActiveEnterTimestampMonotonic --value "$FPM_UNIT")
      if [ "$FPM_AFTER" != "$FPM_BEFORE" ]; then
        FPM_NOTE="plesk-php84-fpm GENSTARTET af pakken selv (postinst condrestart) kl. $(systemctl show -p ActiveEnterTimestamp --value "$FPM_UNIT")"
      else
        log "FPM: pakken genstartede IKKE $FPM_UNIT - genstarter nu"
        if systemctl restart "$FPM_UNIT"; then
          FPM_NOTE="plesk-php84-fpm genstartet af SCRIPTET (pakken gjorde det ikke) kl. $(systemctl show -p ActiveEnterTimestamp --value "$FPM_UNIT")"
        else
          FPM_NOTE="FEJL: systemctl restart $FPM_UNIT mislykkedes!"; ERRORS+=("$FPM_NOTE")
        fi
      fi
      plesk bin php_handler --reread >/dev/null 2>&1 || log "WARN: plesk bin php_handler --reread fejlede"
    fi
  fi
fi

# --- 2b) Tredjepart udenfor Plesk-autoupdate (tilfoejet 2026-10-26 efter audit): cloudflared (CF-tunnel), Imunify, alt-php-internal ---
EXTRA_PKGS=$(dpkg-query -W -f='${binary:Package}\n' 'cloudflared' 'imunify*' 'alt-php-internal*' 2>/dev/null | tr '\n' ' ')
# shellcheck disable=SC2086
EXTRA_PLAN=$(apt-get -s install --only-upgrade $EXTRA_PKGS 2>/dev/null | awk '/^Inst /{print $2}' | tr '\n' ' ')
if [ -n "${EXTRA_PLAN// /}" ]; then
  log "TREDJEPART: opgraderbare pakker: $EXTRA_PLAN"
  if [ "$DRY" = 1 ]; then
    # shellcheck disable=SC2086
    apt-get -s install --only-upgrade $EXTRA_PKGS 2>/dev/null | grep -E '^(Inst|Conf) ' | tee -a "$LOG"
  else
    CF_BEFORE=$(systemctl show -p ActiveEnterTimestampMonotonic --value cloudflared.service 2>/dev/null)
    # shellcheck disable=SC2086
    if apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
         install --only-upgrade $EXTRA_PLAN > "$RUN/aptextra" 2>&1; then
      log "TREDJEPART: apt-get install --only-upgrade OK"
    else
      log "ERROR: tredjeparts-opgradering fejlede (rc=$?)"; ERRORS+=("tredjepart apt-get install fejlede - se log")
    fi
    sed 's/^/    apt| /' "$RUN/aptextra" >> "$LOG"
    if echo " $EXTRA_PLAN" | grep -q ' cloudflared' && [ "$(systemctl show -p ActiveEnterTimestampMonotonic --value cloudflared.service 2>/dev/null)" = "$CF_BEFORE" ]; then
      if systemctl try-restart cloudflared.service; then log "cloudflared genstartet af scriptet (pakken gjorde det ikke)"; else log "ERROR: cloudflared genstart fejlede"; ERRORS+=("cloudflared genstart fejlede"); fi
    fi
  fi
fi

# --- 3) Ubuntu security (unattended-upgrade, samme Allowed-Origins som natkoerslen) ---
if [ "$DRY" = 1 ]; then
  unattended-upgrade --dry-run -v 2>&1 | grep -vE '^(Initial|Allowed)' | sed 's/^/    uu| /' | tee -a "$LOG"
else
  if unattended-upgrade -v > "$RUN/uu" 2>&1; then
    if grep -qiE 'Packages that will be upgraded' "$RUN/uu"; then sed 's/^/    uu| /' "$RUN/uu" >> "$LOG"; else log "Ubuntu: unattended-upgrade - intet at goere"; fi
  else
    log "ERROR: unattended-upgrade rc=$?"; sed 's/^/    uu| /' "$RUN/uu" >> "$LOG"; ERRORS+=("unattended-upgrade fejlede - se log")
  fi
fi

# --- 3b) FPM genstartet af andre end PHP-pakken? (needrestart efter fx zlib/openssl-opdatering - set 23/10 16:45) ---
if [ "$FPM_NOTE" = "ingen PHP-opgradering" ]; then
  FPM_AFTER2=$(systemctl show -p ActiveEnterTimestampMonotonic --value "$FPM_UNIT")
  if [ "$FPM_AFTER2" != "$FPM_BEFORE" ]; then
    FPM_NOTE="ingen PHP-opgradering, men plesk-php84-fpm blev GENSTARTET under koerslen (needrestart efter biblioteks-opdatering) kl. $(systemctl show -p ActiveEnterTimestamp --value "$FPM_UNIT")"
  fi
fi

# --- 4) diff: hvad blev faktisk aendret? ---
snapshot "$RUN/after"
CHANGES=$(awk 'NR==FNR{b[$1]=$2; next} { if (!($1 in b)) print "  " $1 "  (ny) -> " $2; else if (b[$1]!=$2) print "  " $1 "  " b[$1] " -> " $2 }' "$RUN/before" "$RUN/after")
REMOVED=$(awk 'NR==FNR{a[$1]=1; next} !($1 in a){print "  " $1 "  (fjernet)"}' "$RUN/after" "$RUN/before")
[ -n "$REMOVED" ] && CHANGES="$CHANGES"$'\n'"$REMOVED"
N=$(printf '%s\n' "$CHANGES" | grep -c '^  ' || true)
PHPV_AFTER=$("$PHP_BIN" -r 'echo PHP_VERSION;' 2>/dev/null)
log "END: $N pakke(r) aendret; php $PHPV_BEFORE -> $PHPV_AFTER; $FPM_NOTE; fejl=${#ERRORS[@]}"

if [ "$N" -gt 0 ] || [ "${#ERRORS[@]}" -gt 0 ]; then
  SITECHK=""
  # Liveness-tjek DIREKTE mod origin (nginx->apache->FPM) med --resolve: via Cloudflare svarer event/datagaarden 403 til serverens
  # egen IP (CF-challenge), og cbcit.dk staar i /etc/hosts -> egen IP med CF-ORIGIN-cert (ikke offentligt betroet) -> -k. Tjekket er PHP-liveness, ikke TLS.
  ORIGIN_IP=$(getent ahostsv4 server.cbcit.dk 2>/dev/null | awk 'NR==1{print $1}'); ORIGIN_IP=${ORIGIN_IP:-178.104.70.94}
  for u in $SITES; do h=${u#https://}; h=${h%%/*}
    SITECHK+="  $u (origin $ORIGIN_IP) -> HTTP $(curl -ksS -o /dev/null -L --max-time 20 --resolve "$h:443:$ORIGIN_IP" -w '%{http_code}' -A 'cbc-security-updates/1.0' "$u" 2>/dev/null || echo FEJL)"$'\n'; done
  REBOOT="nej"; [ -f /var/run/reboot-required ] && REBOOT="JA - $(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null)"
  PHPCHG="nej"; echo "$CHANGES" | grep -q 'plesk-php' && PHPCHG="JA"
  ERRTXT=""
  if [ "${#ERRORS[@]}" -gt 0 ]; then
    SUBJ="[$HOST] FEJL i sikkerhedsopdatering ($N pakke(r) aendret)"
    ERRTXT="FEJL:"$'\n'"$(printf '  - %s\n' "${ERRORS[@]}")"$'\n'
  else
    SUBJ="[$HOST] Sikkerhedsopdateringer installeret: $N pakke(r) (PHP: $PHPCHG)"
  fi
  # 2026-11-06: fejl, FPM ikke aktiv eller et site != HTTP 200 -> alert (straks); ren opgradering -> digest
  NOTIFY_MODE=digest
  if [ "${#ERRORS[@]}" -gt 0 ] || [ "$(systemctl is-active "$FPM_UNIT")" != active ] || printf '%s\n' "$SITECHK" | grep -vqE 'HTTP 200$|^$'; then NOTIFY_MODE=alert; fi
  mail_out "$SUBJ" <<EOM
cbc-security-updates.sh koerte $(ts) paa $HOST.

Opgraderede pakker (gammel -> ny):
${CHANGES:-  (ingen)}

PHP (plesk-php84): $PHPV_BEFORE -> $PHPV_AFTER
FPM: $FPM_NOTE
FPM-status nu: $(systemctl is-active "$FPM_UNIT") (aktiv siden $(systemctl show -p ActiveEnterTimestamp --value "$FPM_UNIT"))
Genstart af serveren paakraevet: $REBOOT

Sites efter opgradering:
$SITECHK
${ERRTXT}Kilder: Plesk-PHP via apt (repo autoinstall.plesk.com PHP84_17/PHP83_17), Ubuntu via unattended-upgrade.
Fuld log: $LOG   (seneste koersel: grep "$(date '+%Y-%m-%d %H')" $LOG)
Runbook: /root/cbc-hardening-2026-10/README.md  (afsnit "Sikkerhedsopdateringer hver 4. time")
EOM
  log "mail sendt til $TO: $SUBJ"
fi
exit 0
