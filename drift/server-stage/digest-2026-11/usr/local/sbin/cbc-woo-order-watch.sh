#!/usr/bin/env bash
# CBC 2026-10-21: overvaagning af ordre-velocity paa cbcit.dk (card-testing-vaern).
# Koeres hver time via /etc/cron.d/cbc-woo-order-watch. Mailer hvis > THRESHOLD ordrer
# er oprettet den seneste time (baseline: ~2 ordrer/aar). THRESHOLD kan overstyres via env.
set -euo pipefail
THRESHOLD="${THRESHOLD:-5}"
TO="${TO:-johan@cbcit.dk}"
DB=cbcit_prod
export MYSQL_PWD
MYSQL_PWD=$(cat /etc/psa/.psa.shadow)
Q="mysql -uadmin -N $DB -e"

COUNT=$($Q "SELECT COUNT(*) FROM wp_posts WHERE post_type='shop_order' AND post_date_gmt >= UTC_TIMESTAMP() - INTERVAL 60 MINUTE")
if [ "$COUNT" -le "$THRESHOLD" ]; then
  exit 0
fi

DETAIL=$($Q "SELECT pm.meta_value ip, COUNT(*) n, GROUP_CONCAT(p.post_status) st FROM wp_posts p LEFT JOIN wp_postmeta pm ON pm.post_id=p.ID AND pm.meta_key='_customer_ip_address' WHERE p.post_type='shop_order' AND p.post_date_gmt >= UTC_TIMESTAMP() - INTERVAL 60 MINUTE GROUP BY ip ORDER BY n DESC LIMIT 15")
GUARD=$(grep -h 'cbc-checkout-guard' /var/www/vhosts/system/cbcit.dk/logs/error_log 2>/dev/null | tail -20 || true)

# 2026-11-06: via cbc-notify.sh som alert (straks, uaendret adfaerd; emnet faar praefiks "[CBC ALARM] ")
/usr/local/sbin/cbc-notify.sh alert "[cbcit.dk] $COUNT ordrer oprettet den seneste time (loft $THRESHOLD)" woo-order-watch <<EOF
Mulig card-testing paa www.cbcit.dk: $COUNT ordrer oprettet de seneste 60 minutter.

IP / antal / statusser:
$DETAIL

Seneste checkout-guard-log (vhost error_log):
${GUARD:-(ingen)}

Tjek: WooCommerce > Ordrer, Cloudflare > Security > Events, Quickpay Manager.
Script: /usr/local/sbin/cbc-woo-order-watch.sh
EOF
