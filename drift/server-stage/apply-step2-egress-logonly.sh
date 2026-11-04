#!/bin/bash
# TRIN 2 — web-egress-filter i LOG-ONLY. Koeres som root paa cbc-prod.
# Dead-man: om 5 min rulles automatisk tilbage til den gamle regelfil, medmindre dette script
# selv annullerer den efter groen verifikation (eller man koerer: systemctl stop cbc-fw-deadman.timer).
set -uo pipefail
H=/root/cbc-hardening-2026-10; ST=$H/stage; B=$H/backup
say(){ printf '\n== %s\n' "$*"; }
fail(){ echo "FEJL: $*"; echo "Dead-man er aktiv og ruller tilbage om <=5 min. Manuel rollback: bash $H/rollback-step2.sh"; exit 1; }

say "0. dead-man (5 min) -> gendan gammel regelfil + gammelt apply-script"
systemd-run --on-active=300 --unit=cbc-fw-deadman --description="CBC fw dead-man rollback" \
  /bin/sh -c "cp -a $B/cbc_fw.nft.pre-webegress /etc/nftables.d/cbc_fw.nft; cp -a $B/cbc-fw-apply.sh /usr/local/sbin/cbc-fw-apply.sh; /usr/local/sbin/cbc-fw-apply.sh; logger -t cbc-fw-deadman 'ROLLBACK udfoert'" \
  || fail "kunne ikke starte dead-man"

say "1. installer filer"
install -m 644 $ST/etc/cbc-web-egress-hosts.txt /etc/cbc-web-egress-hosts.txt
install -m 750 $ST/usr/local/sbin/cbc-web-egress-refresh.sh /usr/local/sbin/
install -m 750 $ST/usr/local/sbin/cbc-web-egress-mode.sh    /usr/local/sbin/
install -m 750 $ST/usr/local/sbin/cbc-egress-report.sh      /usr/local/sbin/
install -m 750 $ST/usr/local/sbin/cbc-fw-apply.sh           /usr/local/sbin/
install -m 750 $ST/usr/local/sbin/cbc-fw-refresh.sh         /usr/local/sbin/
install -m 644 $ST/etc/systemd/system/cbc-web-egress-refresh.service /etc/systemd/system/
install -m 644 $ST/etc/systemd/system/cbc-web-egress-refresh.timer   /etc/systemd/system/
install -m 644 $ST/etc/nftables.d/cbc_fw.nft /etc/nftables.d/cbc_fw.nft
systemctl daemon-reload

say "2. anvend regelsaet (samme vej som ved boot: cbc-fw-apply.sh)"
/usr/local/sbin/cbc-fw-apply.sh || fail "cbc-fw-apply.sh fejlede"
nft list chain inet cbc_fw web_egress >/dev/null || fail "web_egress mangler efter apply"

say "3. fyld allowlist (foerste refresh)"
/usr/local/sbin/cbc-web-egress-refresh.sh || echo "ADVARSEL: refresh returnerede fejl — se /var/log/cbc-web-egress-refresh.log"
tail -3 /var/log/cbc-web-egress-refresh.log
/usr/local/sbin/cbc-web-egress-mode.sh status
echo "-- allowlist v4:"; nft list set inet cbc_fw web_allow4 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3} (expires [^,]+)?' | sort -u | head -40
echo "-- idempotens-test: refresh igen (maa ikke give nft-fejl)"
/usr/local/sbin/cbc-web-egress-refresh.sh && echo refresh-2-OK
ls -la /etc/nftables.d/cbc_web_egress_elements.nft

say "4. funktionstest som web-uid"
echo "-- tilladt maal (api.wordpress.org:443) som cbcitdk:"
su -s /bin/bash cbcitdk -c 'curl -sS -o /dev/null --max-time 15 -w "%{http_code}\n" https://api.wordpress.org/core/version-check/1.7/' || echo "curl fejlede"
echo "-- IKKE-allowlistet maal (example.com:443) som datagaardendk — skal LYKKES (log-only) og give en log-linje med UID=10002:"
su -s /bin/bash datagaardendk -c 'curl -sS -o /dev/null --max-time 15 -w "%{http_code}\n" https://example.com/' || echo "curl fejlede"
sleep 1
echo "-- journal (cbc-egress-drop, sidste 2 min):"
journalctl -k --since "-2 min" | grep 'cbc-egress-drop:' | sed -E 's/.*(DST=[^ ]+).*(DPT=[^ ]+).*(UID=[^ ]+).*/\1 \2 \3/' | sort | uniq -c
echo "-- tael eksisterende generelle egress-drops (maa ikke eksplodere):"
nft list chain inet cbc_fw output | grep -E 'counter'

say "5. wp-cli som sysuser (cron-sti) virker"
for d in event.cbcit.dk:event.cbcit.dk_x3pjx5okzbn cbcit.dk:cbcitdk datagaarden.dk:datagaardendk; do dom=${d%%:*}; u=${d##*:}
  printf '%s: ' "$dom"; su -s /bin/bash "$u" -c "/opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp --path=/var/www/vhosts/$dom/httpdocs --skip-themes --skip-plugins core version 2>&1"
done

say "6. persistens: boot-fil syntaks + indhold"
nft -c -f /etc/nftables.d/cbc_fw.nft && echo boot-fil-OK
grep -c 'cbc-egress-mode' /etc/nftables.d/cbc_fw.nft

echo
echo ">>> Hvis alt ovenfor er groent OG de tre sites svarer 200 udefra: annuller dead-man med"
echo ">>>   systemctl stop cbc-fw-deadman.timer   (derefter: bash $H/stage/finish-step2.sh)"
echo ">>> Dead-man udloeber ellers om 5 min fra start."
