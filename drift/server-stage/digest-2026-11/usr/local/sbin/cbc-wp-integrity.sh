#!/bin/bash
# CBC WP-integritetstjek (2026-07-22).
# Ugentligt: core+plugin checksum-verifikation mod wordpress.org (alle 3 WP-sites)
# + ventende core/plugin-opdateringer (cbcit+datagaarden; event.cbcit.dk har eget
# notify-script cbc-update-notify.php, mandag 07:30 UTC).
# Mailer KUN naar der er noget at rapportere. Koeres af cbc-wp-integrity.timer.
# Log: /var/log/cbc-wp-integrity.log
set -u

PHP=/opt/plesk/php/8.4/bin/php
WP=/usr/local/bin/wp
MAILTO="johan@cbcit.dk"
MAILFROM="noreply@cbcit.dk"
LOG=/var/log/cbc-wp-integrity.log
TS=$(date '+%F %T')

REPORT=""
ALERT=0       # 1 = checksum-afvigelse/fejl -> ADVARSEL-subjekt
NOTEWORTHY=0  # 1 = der sendes mail

add() { REPORT+="$1"$'\n'; }

# 3. argument er EN samlet streng af wp-argumenter (indre citater bevares).
wpq() {  # <sysuser> <path> "<wp-args>"   -- skip plugins/themes (robust)
  local u="$1" p="$2" args="$3"
  su -s /bin/bash "$u" -c "$PHP -d memory_limit=512M $WP --path=$p --skip-plugins --skip-themes $args" 2>&1
}
wpfull() {  # som wpq men MED plugins indlaest (kraeves af update-tjek)
  local u="$1" p="$2" args="$3"
  su -s /bin/bash "$u" -c "$PHP -d memory_limit=512M $WP --path=$p $args" 2>&1
}

check_site() {  # <label> <sysuser> <path> <tjek_opdateringer 0|1>
  local label="$1" u="$2" p="$3" upd="$4"
  local out rc bad
  add "=== $label ==="

  out=$(wpq "$u" "$p" "core verify-checksums"); rc=$?
  if [ $rc -eq 0 ]; then
    add "core-checksums: OK"
  else
    ALERT=1; NOTEWORTHY=1
    add "core-checksums: PROBLEM (exit $rc):"
    add "$out"
  fi

  out=$(wpq "$u" "$p" "plugin verify-checksums --all"); rc=$?
  # wp-cli's faktiske meddelelser: "Checksum does not match" / "File is missing" / "File was added"
  bad=$(printf '%s\n' "$out" | grep -E "Checksum does not match|File is missing|File was added" || true)
  # Kendt-benigne fund (identificeret 2026-07-22, whitelistet 2026-08-17 pga. alarm-traethed):
  # all-in-one-wp-migration opretter selv 4 beskyttelsesfiler i storage/ - de er ikke en
  # del af wp.org-pakken og flagges ellers som "File was added" i HVER ugerapport.
  bad=$(printf "%s\n" "$bad" | grep -vE "^all-in-one-wp-migration[[:space:]]+storage/(index\\.html|index\\.php|web\\.config|\\.htaccess)[[:space:]]+File was added$" || true)
  if [ -n "$bad" ]; then
    ALERT=1; NOTEWORTHY=1
    add "plugin-checksums: AFVIGELSER FUNDET:"
    add "$bad"
  elif [ $rc -ne 0 ] && ! printf '%s\n' "$out" | grep -qiE "skipped|Verified"; then
    ALERT=1; NOTEWORTHY=1
    add "plugin-checksums: verifikation FEJLEDE (exit $rc), sidste output:"
    add "$(printf '%s\n' "$out" | tail -5)"
  else
    add "plugin-checksums: OK ($(printf '%s\n' "$out" | grep -oE 'Verified [0-9]+ of [0-9]+ plugins' | head -1 | grep . || echo 'verificeret'); ikke-wp.org-plugins kan ikke tjekkes og skippes)"
  fi

  if [ "$upd" = "1" ]; then
    wpfull "$u" "$p" "eval 'wp_version_check(); wp_update_plugins();'" >/dev/null 2>&1
    out=$(wpfull "$u" "$p" "core check-update --format=csv" | grep -E '^[0-9]+\.' || true)
    if [ -n "$out" ]; then
      NOTEWORTHY=1
      add "ventende CORE-opdatering(er): "
      add "$out"
    fi
    out=$(wpfull "$u" "$p" "plugin list --update=available --fields=name,version,update_version --format=csv" | grep -E '^[a-z0-9_-]+,' || true)
    if [ -n "$out" ]; then
      NOTEWORTHY=1
      add "ventende plugin-opdateringer (navn,nuvaerende,ny):"
      add "$out"
    else
      add "plugin-opdateringer: ingen ventende"
    fi
  fi
  add ""
}

check_site "event.cbcit.dk" "event.cbcit.dk_x3pjx5okzbn" "/var/www/vhosts/event.cbcit.dk/httpdocs" 0
check_site "cbcit.dk"       "cbcitdk"                    "/var/www/vhosts/cbcit.dk/httpdocs"       1
check_site "datagaarden.dk" "datagaardendk"              "/var/www/vhosts/datagaarden.dk/httpdocs" 1

echo "[$TS] alert=$ALERT noteworthy=$NOTEWORTHY" >> "$LOG"
# Fuld rapport gemmes altid lokalt (fejlsoegning + hvis mail-kaeden fejler)
printf '[%s]\n%s\n' "$TS" "$REPORT" > /var/log/cbc-wp-integrity-last.txt

if [ "$NOTEWORTHY" = "1" ]; then
  if [ "$ALERT" = "1" ]; then
    SUBJ="[CBC] ADVARSEL: WP-integritetsafvigelse paa server.cbcit.dk"
  else
    SUBJ="[CBC] WP-status: ventende opdateringer (cbcit/datagaarden)"
  fi
  # 2026-11-06: via cbc-notify.sh - checksum-afvigelse (ALERT=1) -> alert (straks); kun ventende opdateringer -> digest
  NMODE=digest; [ "$ALERT" = "1" ] && NMODE=alert
  {
    echo "Ugentligt WP-integritetstjek $TS paa server.cbcit.dk"
    echo "(checksum-verifikation mod wordpress.org + ventende opdateringer)"
    echo
    printf '%s\n' "$REPORT"
    echo "-- Genereret af /usr/local/sbin/cbc-wp-integrity.sh (cbc-wp-integrity.timer, man 05:15)"
  } | /usr/local/sbin/cbc-notify.sh "$NMODE" "$SUBJ" wp-integrity
fi
exit 0
