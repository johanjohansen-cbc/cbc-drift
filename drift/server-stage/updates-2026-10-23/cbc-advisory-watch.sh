#!/usr/bin/env bash
# CBC 2026-10-23: advisory-overvaagning af prod (server.cbcit.dk) - PHP, WordPress-kerne, plugins, Plesk.
#
# Tjek (kun bash + curl + Plesks PHP-CLI til JSON - ingen nye runtimes, jq findes ikke paa boksen):
#   1) PHP:    php.net (releases/index.php?json&version=8.4) vs. /opt/plesk/php/8.4/bin/php; viser ogsaa Plesk-repoets kandidat
#   2) WP:     api.wordpress.org/core/version-check/1.7/ vs. `wp core version` paa alle tre sites (som hvert sites sysuser)
#   3) Plugins: `wp plugin list --update=available` pr. site; hver opdatering slaas op i wp.org's plugin-API og den nyeste
#              changelog-tekst scannes for sikkerheds-ord (security/vulnerab/XSS/CSRF/SQLi/CVE ...). Premium-plugins uden
#              wp.org-side markeres "ikke paa wp.org". NB: Wordfence' gratis saarbarhedsfeed er lukket (HTTP 410/401, okt. 2026),
#              og WPScan/Patchstack kraever API-noegle -> changelog-heuristikken er det bedste noegle-frie signal.
#   4) Plesk:  samme kommandoer som Plesks egen natkoersel, blot read-only:
#              autoinstaller --show-upgradable-components / --show-releases (XML). Koerer under cbc-security-updates-laasen.
#
# Tilstande:  check   (dagligt 07:15, ikke mandag)  -> mail KUN ved afvigelse. Plugin-opdateringer mailes den dag de
#                                                       foerst ses eller hvis changelog ligner sikkerhed (state i /var/lib/cbc-advisory).
#             weekly  (mandag 07:30)                  -> "alt OK"/status-mail ALTID, saa man ved at overvaagningen lever.
#             show    (manuelt)                       -> fuld rapport paa stdout, ingen mail, ingen state-aendring.
# Mail: johan@cbcit.dk via /usr/sbin/sendmail (Postfix -> Brevo). Log: /var/log/cbc-advisory-watch.log
set -uo pipefail
export LC_ALL=C.UTF-8 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MODE="${1:-check}"
case "$MODE" in check|weekly|show) ;; *) echo "brug: $0 check|weekly|show" >&2; exit 2;; esac

TO="${TO:-johan@cbcit.dk}"
FROM="cbc-advisory-watch@server.cbcit.dk"
HOST=$(hostname -f 2>/dev/null || hostname)
PHP=/opt/plesk/php/8.4/bin/php
WPCLI="$PHP -d memory_limit=512M /usr/local/bin/wp"
STATE=/var/lib/cbc-advisory
LOG=/var/log/cbc-advisory-watch.log
SECLOG=/var/log/cbc-security-updates.log
LOCK=/run/lock/cbc-security-updates.lock          # deles med cbc-security-updates.sh (begge roerer apt)
CURL="curl -gsS --max-time 30 -A cbc-advisory-watch/1.0"
SITES="event.cbcit.dk cbcit.dk datagaarden.dk"
declare -A DOCROOT=([event.cbcit.dk]=/var/www/vhosts/event.cbcit.dk/httpdocs
                    [cbcit.dk]=/var/www/vhosts/cbcit.dk/httpdocs
                    [datagaarden.dk]=/var/www/vhosts/datagaarden.dk/httpdocs)
# Ordgraenser (\b) saa fx "WooCommeRCE" ikke matcher "rce".
SECWORDS='\b(secur[a-z]*|vulnerab[a-z]*|xss|cross-site|csrf|sql[ -]?injection|injection|rce|remote code execution|privilege escalation|escalat[a-z]*|exploit[a-z]*|cve-[0-9]+|saarbar[a-z]*|sårbar[a-z]*|sikkerhed[a-z]*|hardening|unauthoriz[a-z]*|unauthenticat[a-z]*|sanitiz[a-z]*|escap(e|ing)[a-z]*)\b'

[ "$MODE" = show ] || { mkdir -p "$STATE"; touch "$LOG"; chmod 640 "$LOG"; }
ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { [ "$MODE" = show ] && return 0; printf '%s %s\n' "$(ts)" "$*" >> "$LOG"; }
# jget <sti.med.punkter>  - laeser JSON paa stdin, skriver skalar eller JSON
jget() { "$PHP" -r '$j=json_decode(stream_get_contents(STDIN),true); foreach(explode(".",$argv[1]) as $k){ if(!is_array($j)||!array_key_exists($k,$j)) exit(1); $j=$j[$k]; } echo is_scalar($j)?$j:json_encode($j,JSON_UNESCAPED_UNICODE);' -- "$1" 2>/dev/null; }
# wp_site <domaene> <wp-args...>  - wp-cli som sitets sysuser, temaer skippes
wp_site() { local d=$1; shift; local u; u=$(stat -c %U "${DOCROOT[$d]}"); su -s /bin/bash "$u" -c "cd '${DOCROOT[$d]}' && $WPCLI --skip-themes $*" 2>/dev/null; }
vlt() { dpkg --compare-versions "$1" lt "$2"; }   # version $1 < $2 ?

ALERTS=(); STATUS=(); PENDING=()
alert()  { ALERTS+=("$1"); }
status() { STATUS+=("$1"); }

# ---------- 1) PHP ----------
PHP_LOCAL=$("$PHP" -r 'echo PHP_VERSION;' 2>/dev/null)
PHP_JSON=$($CURL "https://www.php.net/releases/index.php?json&version=8.4" 2>/dev/null)
PHP_LATEST=$(printf '%s' "$PHP_JSON" | jget version)
PHP_DATE=$(printf '%s' "$PHP_JSON" | jget date)
PHP_TAGS=$(printf '%s' "$PHP_JSON" | jget tags)
PHP_CAND=$(apt-cache policy plesk-php84 2>/dev/null | awk '/Candidate:/{print $2}' | cut -d- -f1)
APT_STAMP=$(stat -c %y /var/lib/apt/periodic/update-success-stamp 2>/dev/null | cut -c1-16)
if [ -z "$PHP_LATEST" ]; then
  alert "PHP: kunne ikke hente seneste 8.4-version fra php.net (netvaerk/format?). Serveren koerer $PHP_LOCAL."
  status "PHP 8.4: server $PHP_LOCAL - php.net-opslag FEJLEDE"
elif vlt "$PHP_LOCAL" "$PHP_LATEST"; then
  if [ -n "$PHP_CAND" ] && ! vlt "$PHP_CAND" "$PHP_LATEST"; then
    HOWTO="Plesk-repoet HAR $PHP_CAND -> koer nu:  /usr/local/sbin/cbc-security-updates.sh   (eller: apt-get update && apt-get install --only-upgrade 'plesk-php84-*')"
  else
    HOWTO="Plesk-repoet har endnu kun ${PHP_CAND:-?} (apt-lister fra $APT_STAMP). Plesk pakker typisk inden for timer-1 doegn; cbc-security-updates.sh henter den automatisk inden 4 t derefter. Tjek manuelt: apt-get update && apt-cache policy plesk-php84"
  fi
  alert "PHP: php.net har udgivet $PHP_LATEST ($PHP_DATE, tags $PHP_TAGS) - serveren koerer $PHP_LOCAL. $HOWTO"
  status "PHP 8.4: server $PHP_LOCAL < php.net $PHP_LATEST  (Plesk-kandidat ${PHP_CAND:-?})"
else
  status "PHP 8.4: server $PHP_LOCAL = php.net $PHP_LATEST ($PHP_DATE) - OK"
fi

# ---------- 2) WordPress-kerne ----------
WP_LATEST=$($CURL "https://api.wordpress.org/core/version-check/1.7/" 2>/dev/null | jget offers.0.version)
if [ -z "$WP_LATEST" ]; then
  alert "WordPress: kunne ikke hente seneste version fra api.wordpress.org."
fi
for s in $SITES; do
  v=$(wp_site "$s" core version | tail -1)
  if [ -z "$v" ]; then
    alert "WordPress $s: 'wp core version' gav intet svar - wp-cli/sitet fejler?"; status "WP $s: wp-cli FEJL"; continue
  fi
  if [ -n "$WP_LATEST" ] && vlt "$v" "$WP_LATEST"; then
    u=$(stat -c %U "${DOCROOT[$s]}")
    note=""; [ "$s" = event.cbcit.dk ] && note=" (event har DISALLOW_FILE_MODS=1 -> ingen auto-update; manuelt via wp-cli, jf. deploy-runbook)"
    alert "WordPress $s: seneste er $WP_LATEST, sitet koerer $v.$note Opdater:  su -s /bin/bash $u -c \"cd ${DOCROOT[$s]} && $WPCLI core update --skip-themes && $WPCLI core update-db --skip-themes\""
    status "WP $s: $v < $WP_LATEST"
  else
    status "WP $s: $v (seneste ${WP_LATEST:-?}) - OK"
  fi
done

# ---------- 3) Plugin-opdateringer ----------
REPORTED="$STATE/reported-plugins.txt"; [ "$MODE" = show ] || touch "$REPORTED"
NEWREP=""
plugin_flag() { # $1 slug $2 ny version -> tekst
  local j cl code
  j=$($CURL -w '\n%{http_code}' "https://api.wordpress.org/plugins/info/1.2/?action=plugin_information&request[slug]=$1&request[fields][sections]=1&request[fields][versions]=0&request[fields][banners]=0&request[fields][screenshots]=0" 2>/dev/null)
  code=${j##*$'\n'}; j=${j%$'\n'*}
  if [ "$code" != 200 ] || printf '%s' "$j" | grep -q '"error"'; then echo "ikke paa wp.org (premium) - tjek leverandoerens changelog"; return; fi
  cl=$(printf '%s' "$j" | "$PHP" -r '$j=json_decode(stream_get_contents(STDIN),true); $c=$j["sections"]["changelog"]??""; $c=preg_replace("/\s+/"," ",strip_tags(html_entity_decode($c))); echo substr($c,0,1500);' 2>/dev/null)
  [ -z "$cl" ] && { echo "wp.org: ingen changelog"; return; }
  if printf '%s' "$cl" | grep -qiE "$SECWORDS"; then
    echo "SIKKERHED? changelog naevner: $(printf '%s' "$cl" | grep -oiE "[^.]{0,60}($SECWORDS)[^.]{0,60}" | head -1 | tr -s ' ')"
  else echo "changelog uden sikkerheds-ord"; fi
}
for s in $SITES; do
  csv=$(wp_site "$s" plugin list --update=available --fields=name,version,update_version --format=csv | tail -n +2)
  [ -z "$csv" ] && { status "Plugins $s: ingen opdateringer afventer - OK"; continue; }
  n=0; u=$(stat -c %U "${DOCROOT[$s]}")
  while IFS=, read -r name ver new; do
    [ -z "$name" ] && continue; n=$((n+1))
    flag=$(plugin_flag "$name" "$new")
    line="$s: $name $ver -> $new   [$flag]"
    PENDING+=("$line")
    key="$s|$name|$new"
    isnew=1; [ "$MODE" != show ] && grep -qxF "$key" "$REPORTED" && isnew=0
    if [[ "$flag" == SIKKERHED* ]] || [ "$isnew" = 1 ]; then
      if [[ "$flag" == "ikke paa wp.org"* ]]; then how="opdater via wp-admin > Plugins paa $s (leverandoer-server; host skal vaere paa egress-allowlisten /etc/cbc-web-egress-hosts.txt)"
      else how="su -s /bin/bash $u -c \"cd ${DOCROOT[$s]} && $WPCLI plugin update $name --skip-themes\""; fi
      alert "Plugin $line  ->  $how"
    fi
    NEWREP+="$key"$'\n'
  done <<< "$csv"
  status "Plugins $s: $n opdatering(er) afventer"
done
[ "$MODE" = show ] || { printf '%s' "$NEWREP" | sort -u > "$REPORTED.tmp" && mv "$REPORTED.tmp" "$REPORTED"; }

# ---------- 4) Plesk ----------
PLESK_VER=$(plesk version 2>/dev/null | awk '/Product version/{print $NF}')
PLESK_BASE=${PLESK_VER%.*}   # 18.0.81.4 -> 18.0.81
if pgrep -f '/opt/psa/admin/bin/autoinstaller' >/dev/null; then
  status "Plesk $PLESK_VER: tjek sprunget over (Plesks autoinstaller koerer lige nu)"
else
  AI="/opt/psa/admin/bin/autoinstaller --select-product-id plesk"
  COMP=$(flock -w 180 "$LOCK" $AI --select-release-current --show-upgradable-components --enable-xml-output 2>/dev/null | grep -o '<?xml.*' | grep -oE '<component [^>]*>' | sed -E 's/.*name="([^"]+)".*/\1/' | tr '\n' ' ')
  # XML: <release id="PLESK_18_0_81" codename="Obsidian" action="up2date"><description>..</description><version>18.0.81</version></release>
  REL=$(flock -w 180 "$LOCK" $AI --show-releases --enable-xml-output --branch release,stable 2>/dev/null | grep -o '<?xml.*' | grep -oE '<version>[0-9.]+</version>' | grep -oE '[0-9.]+' | sort -V | tail -1)
  if [ -n "${COMP// /}" ]; then
    alert "Plesk $PLESK_VER: opdaterede komponenter klar i Plesks repo: $COMP. Plesk installerer dem selv i nat ca. 06:25; nu:  plesk installer update   (PHP-komponenter tager cbc-security-updates.sh inden 4 t)"
    status "Plesk $PLESK_VER: komponent-opdateringer klar: $COMP"
  else
    status "Plesk $PLESK_VER: ingen komponent-opdateringer - OK"
  fi
  if [ -n "$REL" ] && vlt "$PLESK_BASE" "$REL"; then
    alert "Plesk: ny udgave $REL findes (installeret $PLESK_VER). Ny udgave installeres IKKE automatisk - planlaeg:  plesk installer upgrade   (backup foerst; mellem konferencer)"
    status "Plesk: nyeste udgave $REL > installeret $PLESK_BASE"
  elif [ -n "$REL" ]; then status "Plesk: nyeste udgave $REL = installeret - OK"; else status "Plesk: release-opslag gav intet svar"; fi
fi

# ---------- 5) Server-status (info) ----------
[ -f /var/run/reboot-required ] && alert "Server: genstart paakraevet ($(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null)) - planlaeg 'reboot' uden for aabningstid."
UPG=$(apt list --upgradable 2>/dev/null | tail -n +2 | awk -F/ '{print $1}' | tr '\n' ' ')
status "Ubuntu/apt: $(echo "$UPG" | wc -w) pakke(r) kan opgraderes (ikke-security haandteres ikke automatisk): ${UPG:-ingen}"
LASTRUN=$(grep -E ' (START|END|SKIP)' "$SECLOG" 2>/dev/null | tail -1 | cut -c1-120)
LASTUPG=$(grep -E ' END: [1-9][0-9]* pakke' "$SECLOG" 2>/dev/null | tail -1 | cut -c1-160)
status "cbc-security-updates (hver 4. t): seneste koersel: ${LASTRUN:-ingen log endnu}"
status "cbc-security-updates: seneste faktiske opgradering: ${LASTUPG:-ingen siden installation}"
EGR=$(/usr/local/sbin/cbc-web-egress-mode.sh status 2>/dev/null || echo 'status-kommando ikke tilgaengelig')
status "Egress-filter: ${EGR%%$'\n'*}"

# ---------- rapport ----------
NA=${#ALERTS[@]}
REPORT="Advisory-rapport $(ts) - $HOST (tilstand: $MODE)
"
if [ "$NA" -gt 0 ]; then
  REPORT+="
AFVIGELSER ($NA) - hvad er nyt, hvad koerer, hvad goer du:
$(for a in "${ALERTS[@]}"; do printf '  * %s\n\n' "$a"; done)"
else
  REPORT+="
Ingen afvigelser: PHP, WordPress-kerne, plugins og Plesk er paa seneste kendte version (eller allerede rapporteret).
"
fi
REPORT+="
STATUS:
$(printf '  - %s\n' "${STATUS[@]}")
"
if [ "${#PENDING[@]}" -gt 0 ]; then
  REPORT+="
Afventende plugin-opdateringer (alle):
$(printf '  - %s\n' "${PENDING[@]}")
"
fi
REPORT+="
Kilder: php.net releases-JSON, api.wordpress.org (version-check + plugin-info), Plesk autoinstaller (read-only), wp-cli som sysuser.
Script: /usr/local/sbin/cbc-advisory-watch.sh  (check dagligt 07:15 / weekly mandag 07:30 / show = manuel)   Log: $LOG
Runbook: /root/cbc-hardening-2026-10/README.md"

[ "$MODE" = show ] || printf '%s\n' "$REPORT" > "$STATE/last-report.txt"
log "$MODE: $NA afvigelse(r); $(printf '%s; ' "${STATUS[@]}" | cut -c1-300)"

send() { { printf 'To: %s\nFrom: %s\nSubject: %s\nContent-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: 8bit\n\n' "$TO" "$FROM" "$1"; printf '%s\n' "$REPORT"; } | /usr/sbin/sendmail -t; log "mail sendt: $1"; }
case "$MODE" in
  show)   printf '%s\n' "$REPORT" ;;
  check)  [ "$NA" -gt 0 ] && send "[$HOST] Advisory: $NA afvigelse(r) - PHP/WordPress/plugins/Plesk" ;;
  weekly) if [ "$NA" -gt 0 ]; then send "[$HOST] Ugentlig status: $NA afvigelse(r) kraever handling"; else send "[$HOST] Ugentlig status: alt OK (PHP $PHP_LOCAL, WP ${WP_LATEST:-?}, Plesk $PLESK_VER)"; fi ;;
esac
exit 0
