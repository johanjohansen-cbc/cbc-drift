#!/bin/bash
# TRIN 3 — disable_functions (exec-familien) pr. domaene via Plesk per-domaene PHP-indstillinger
# (= php_value[disable_functions] i FPM-poolen; CLI/wp-cli UROERT). Raekkefoelge: datagaarden -> cbcit -> event.
# Brug: apply-step3-php-disable-functions.sh [domaene ...]   (default: alle tre i raekkefoelge)
set -uo pipefail
H=/root/cbc-hardening-2026-10; ST=$H/stage
INI=$ST/php/cbc-php-hardening.ini
WP="/opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp"
say(){ printf '\n== %s\n' "$*"; }
sysuser(){ case "$1" in event.cbcit.dk) echo event.cbcit.dk_x3pjx5okzbn;; cbcit.dk) echo cbcitdk;; datagaarden.dk) echo datagaardendk;; esac; }
DOMS=${*:-"datagaarden.dk cbcit.dk event.cbcit.dk"}

for d in $DOMS; do
  u=$(sysuser "$d"); doc=/var/www/vhosts/$d/httpdocs
  say "$d: anvend PHP-indstillinger ($INI)"
  cat "$INI"
  plesk bin site --update-php-settings "$d" -settings "$INI" || { echo "FEJL: plesk update-php-settings $d"; exit 1; }
  echo "-- pool-conf nu:"; grep -E 'disable_functions|post_max_size|upload_max_filesize' /opt/plesk/php/8.4/etc/php-fpm.d/$d.conf
  systemctl is-active plesk-php84-fpm

  say "$d: FPM-verifikation gennem webserveren (midlertidig fil, slettes straks)"
  tf="cbc-df-check-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n').php"
  cat > "$doc/$tf" <<'PHP'
<?php header('Content-Type: text/plain'); header('X-Robots-Tag: noindex');
$f=['exec','shell_exec','system','passthru','proc_open','popen','pcntl_exec','opcache_get_status','mail','curl_init'];
echo 'sapi=',php_sapi_name(),' php=',PHP_VERSION,"\n";
foreach($f as $x) echo $x,'=',(function_exists($x)?'ENABLED':'disabled'),"\n";
echo 'disable_functions=',ini_get('disable_functions'),"\n";
echo 'post_max_size=',ini_get('post_max_size'),' upload_max_filesize=',ini_get('upload_max_filesize'),' memory_limit=',ini_get('memory_limit'),"\n";
echo 'session.upload_progress.enabled=',ini_get('session.upload_progress.enabled'),"\n";
PHP
  chown "$u:psacln" "$doc/$tf"; chmod 600 "$doc/$tf"
  host=$d; [ "$d" = cbcit.dk ] && host=www.cbcit.dk; [ "$d" = datagaarden.dk ] && host=www.datagaarden.dk
  curl -sk --max-time 20 --resolve "$host:443:178.104.70.94" "https://$host/$tf" -w '\nHTTP %{http_code}\n'
  rm -f "$doc/$tf"; [ -e "$doc/$tf" ] && echo "ADVARSEL: testfil ikke slettet!" || echo "testfil slettet"

  say "$d: wp-cli (CLI-SAPI, maa vaere uroert)"
  su -s /bin/bash "$u" -c "$WP --path=$doc --skip-themes --skip-plugins core version 2>&1; $WP --path=$doc --skip-themes --skip-plugins eval 'echo \"cli disable_functions=[\".ini_get(\"disable_functions\").\"] proc_open=\".(function_exists(\"proc_open\")?\"ok\":\"MANGLER\").PHP_EOL;' 2>&1"

  say "$d: forside via origin (status)"
  curl -sk -o /dev/null --max-time 20 --resolve "$host:443:178.104.70.94" -A 'Mozilla/5.0 cbc-check' "https://$host/" -w "origin HTTP %{http_code}\n"
done

say "deploy-verifikation event.cbcit.dk (deploy.sh's tjek, uden kodeaendring)"
u=event.cbcit.dk_x3pjx5okzbn; doc=/var/www/vhosts/event.cbcit.dk/httpdocs
su -s /bin/bash $u -c "$WP --path=$doc plugin get cbc-event-planner --field=version; $WP --path=$doc cbc db status | head -2; echo \"cbc_-cron-events: \$($WP --path=$doc cron event list --fields=hook | grep -c cbc_)\"; $WP --path=$doc db export /dev/null --quiet && echo 'wp db export (mysqldump via proc_open): OK'"
echo
echo ">>> Rollback: bash $H/rollback-step3.sh [domaene]"
