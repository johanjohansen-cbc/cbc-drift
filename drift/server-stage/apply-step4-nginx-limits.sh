#!/bin/bash
# TRIN 4 — request-graenser i nginx pr. vhost. Raekkefoelge: datagaarden -> cbcit -> event.
#  a) client_max_body_size 8M via Plesks per-domaene-indstilling (Plesk genererer nginx.conf; duplikat i
#     vhost_nginx.conf er ikke muligt).  Rollback-vaerdi: 134217728 (Plesk-default 128M).
#  b) client_body_timeout/client_header_timeout 15s, client_header_buffer_size 1k,
#     large_client_header_buffers 2 8k i vhost_nginx.conf  ->  plesk repair web <dom> -y.
# Brug: apply-step4-nginx-limits.sh [domaene ...]
set -uo pipefail
H=/root/cbc-hardening-2026-10; ST=$H/stage; B=$H/backup
SNIP=$ST/nginx/limits.snippet
say(){ printf '\n== %s\n' "$*"; }
DOMS=${*:-"datagaarden.dk cbcit.dk event.cbcit.dk"}

for d in $DOMS; do
  host=$d; [ "$d" = cbcit.dk ] && host=www.cbcit.dk; [ "$d" = datagaarden.dk ] && host=www.datagaarden.dk
  VH=/var/www/vhosts/system/$d/conf/vhost_nginx.conf

  say "$d (a): client_max_body_size -> 8388608 via Plesk"
  plesk bin subscription --update-web-server-settings "$d" -nginx-client-max-body-size 8388608 || { echo "FEJL: plesk update-web-server-settings $d"; exit 1; }

  say "$d (b): timeouts/header-buffere i vhost_nginx.conf"
  if grep -q 'CBC blast-radius 2026-10-22' "$VH"; then echo "snippet findes allerede — springer over"; else
    cp -a "$VH" "$B/vhost_nginx.conf.$d.pre-limits-$(date +%H%M%S)"
    cat "$SNIP" >> "$VH"
  fi
  tail -6 "$VH"
  plesk repair web "$d" -y >/tmp/cbc-repair-$d.log 2>&1; rc=$?; tail -3 /tmp/cbc-repair-$d.log; rm -f /tmp/cbc-repair-$d.log
  [ $rc -eq 0 ] || { echo "FEJL: plesk repair web $d (rc=$rc) — rollback: bash $H/rollback-step4.sh $d"; exit 1; }
  nginx -t 2>&1 | tail -1

  say "$d: effektiv nginx-konfig"
  grep -nE 'client_max_body_size|client_body_timeout|client_header_timeout|client_header_buffer_size|large_client_header_buffers' /var/www/vhosts/system/$d/conf/nginx.conf
  grep -nE 'client_body_timeout|client_header_buffer_size|large_client_header_buffers' "$VH" | head -3

  say "$d: test via origin — forside 200, 9 MB POST -> 413, 1 MB POST -> ikke 413"
  curl -sk -o /dev/null --max-time 20 --resolve "$host:443:178.104.70.94" -A 'Mozilla/5.0 cbc-check' "https://$host/" -w "forside HTTP %{http_code}\n"
  head -c 9437184 /dev/zero | curl -sk -o /dev/null --max-time 30 --resolve "$host:443:178.104.70.94" -A 'Mozilla/5.0 cbc-check' -H 'Content-Type: application/octet-stream' --data-binary @- "https://$host/" -w "POST 9MB  HTTP %{http_code}\n"
  head -c 1048576 /dev/zero | curl -sk -o /dev/null --max-time 30 --resolve "$host:443:178.104.70.94" -A 'Mozilla/5.0 cbc-check' -H 'Content-Type: application/octet-stream' --data-binary @- "https://$host/" -w "POST 1MB  HTTP %{http_code}\n"
  curl -sk -o /dev/null --max-time 20 --resolve "$host:443:178.104.70.94" -A 'Mozilla/5.0 cbc-check' -H "Cookie: big=$(head -c 20000 /dev/zero | tr '\0' 'a')" "https://$host/" -w "20 kB cookie-header HTTP %{http_code} (forventet 400/494)\n"
  curl -sk -o /dev/null --max-time 20 --resolve "$host:443:178.104.70.94" -A 'Mozilla/5.0 cbc-check' -H "Cookie: ok=$(head -c 3000 /dev/zero | tr '\0' 'a')" "https://$host/" -w "3 kB cookie-header  HTTP %{http_code} (forventet 200)\n"
done

say "FPM-pools uroerte af repair? (disable_functions skal stadig vaere udvidet)"
grep -H disable_functions /opt/plesk/php/8.4/etc/php-fpm.d/{event.cbcit.dk,cbcit.dk,datagaarden.dk}.conf
systemctl is-active nginx apache2 plesk-php84-fpm | paste - - -
echo
echo ">>> Rollback: bash $H/rollback-step4.sh [domaene]"
