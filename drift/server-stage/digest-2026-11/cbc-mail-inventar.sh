#!/bin/bash
# cbc-mail-inventar.sh — READ-ONLY inventar over alt der kan sende mail fra server.cbcit.dk.
#   ssh cbc-prod 'bash -s' < cbc-mail-inventar.sh > 00-live-inventar.txt 2>&1
# Ændrer intet. Secrets (sasl_passwd, healthchecks-URL'er, tokens) filtreres fra.

H(){ printf '\n\n######## %s\n' "$*"; }
C(){ printf '\n$ %s\n' "$*"; eval "$*" 2>&1 | grep -viE 'password|passwd|sasl|token|hc-ping\.com|healthchecks\.io/ping|api[_-]?key' | head -${LIM:-120}; }

echo "CBC mail-inventar — $(hostname) — $(date -Is)"

H "1. Cron/timers"
C 'cat /etc/cron.d/cbc-*'
C 'systemctl list-timers --all --no-pager | grep -E "cbc-|apt|plesk|imunify|certbot|fstrim|e2scrub"'
C 'ls -1 /etc/cron.d /etc/cron.daily /etc/cron.weekly /etc/cron.hourly'
C 'cat /etc/crontab'
for u in root psaadm event.cbcit.dk_x3pjx5okzbn cbcitdk datagaardendk; do C "crontab -l -u $u"; done
C 'grep -rn MAILTO /etc/crontab /etc/cron.d/ /var/spool/cron/crontabs/ 2>/dev/null'

H "2. Mail-afsendere i egne scripts"
C 'grep -lE "sendmail|mail -s|mailx|cbc-notify" /usr/local/sbin/*.sh /usr/local/bin/*.sh /etc/cron.daily/* /etc/cron.weekly/* 2>/dev/null'
for f in $(grep -lE "sendmail|mail -s|mailx" /usr/local/sbin/*.sh /usr/local/bin/*.sh 2>/dev/null); do C "grep -nE 'TO=|ALERT=|FROM=|Subject|sendmail|mail -s' $f"; done
C 'ls -la /var/lib/cbc-advisory /var/spool/cbc-* /var/log/cbc-* 2>/dev/null'
C 'cat /etc/cron.daily/dmarc-report 2>/dev/null'
C 'ls /etc/logwatch 2>/dev/null; dpkg -l | grep -E "logwatch|opendmarc|mailutils|bsd-mailx|s-nail" | awk "{print \$2, \$3}"'

H "3. Postfix"
C 'postconf -n'
C 'postconf -h myorigin mydestination inet_interfaces'
C 'cat /etc/aliases'
C 'ls -la /etc/postfix/'
C 'ls -la /var/log/mail.log* /var/log/maillog* 2>/dev/null'
LIM=60 C 'zgrep -hE "to=<johan@cbcit.dk>" /var/log/mail.log* 2>/dev/null | grep -oE "from=<[^>]*>" | sort | uniq -c | sort -rn'
LIM=60 C 'zgrep -hE "to=<johan@cbcit.dk>" /var/log/mail.log* 2>/dev/null | wc -l; zgrep -hE "to=<johan@cbcit.dk>" /var/log/mail.log* 2>/dev/null | awk "{print \$1}" | cut -c1-10 | sort | uniq -c | tail -30'
LIM=60 C 'zgrep -hE "to=<[^>]*>" /var/log/mail.log* 2>/dev/null | grep -oE "to=<[^>]*>" | sort | uniq -c | sort -rn | head -20'
LIM=80 C 'grep -hE "mail sendt|Subject" /var/log/cbc-*.log 2>/dev/null | sed -E "s/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:+]+//" | sort | uniq -c | sort -rn'

H "4. Plesk-notifikationer"
C 'plesk db "SHOW TABLES LIKE \"%otif%\""'
C 'plesk db "SELECT * FROM Notifications" 2>/dev/null'
C 'plesk db "SELECT last, period, rotation, remoteStorage, email, suspend FROM BackupsScheduled\G"'
C 'plesk bin admin --info 2>/dev/null | grep -iE "mail|email"'
C 'plesk bin server_pref --show 2>/dev/null | grep -iE "mail|notif|report"'
C 'grep -rlE "johan@cbcit.dk" /etc/psa /opt/psa/admin/conf /usr/local/psa/admin/conf /etc/sw /opt/psa/var/modules 2>/dev/null'
C 'plesk ext --list 2>/dev/null'
C 'plesk db "SELECT name,value FROM misc WHERE name LIKE \"%mail%\" OR name LIKE \"%notif%\" OR name LIKE \"%report%\" OR name LIKE \"%health%\""'

H "5. Imunify360"
C 'imunify360-agent config show 2>/dev/null | grep -iE -A8 "ADMIN_CONTACTS|NOTIFICATIONS|MALWARE_SCAN_SCHEDULE|ERROR_REPORTING|ADMIN_NOTIF"'
C 'imunify360-agent notifications-config show 2>/dev/null'

H "6. unattended-upgrades / apt"
C 'grep -nE "^Unattended-Upgrade::(Mail|MailReport|MailOnlyOnError|Automatic-Reboot)" /etc/apt/apt.conf.d/50unattended-upgrades'
C 'cat /etc/apt/apt.conf.d/20auto-upgrades'
C 'ls /etc/apt/apt.conf.d/ | grep -i cbc; cat /etc/apt/apt.conf.d/*cbc* 2>/dev/null'
C 'ls /var/run/reboot-required* 2>/dev/null'

H "7. fail2ban"
C 'grep -nE "^(action|destemail|sender|banaction)" /etc/fail2ban/jail.local /etc/fail2ban/jail.conf /etc/fail2ban/jail.d/* 2>/dev/null'
C 'fail2ban-client status'

H "8. Plesk-sites / sysusers"
C 'ls /var/www/vhosts/'
C 'for d in event.cbcit.dk cbcit.dk datagaarden.dk; do echo "$d -> $(stat -c %U /var/www/vhosts/$d/httpdocs)"; done'

H "9. WordPress pr. site"
WP='/opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp --skip-themes --skip-plugins'
WPP='/opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp --skip-themes'
for d in event.cbcit.dk cbcit.dk datagaarden.dk; do
  u=$(stat -c %U /var/www/vhosts/$d/httpdocs); r=/var/www/vhosts/$d/httpdocs
  W(){ su -s /bin/bash "$u" -c "cd $r && $WP $1" 2>&1 | head -${LIM:-60}; }
  WPL(){ su -s /bin/bash "$u" -c "cd $r && $WPP $1" 2>&1 | head -${LIM:-80}; }
  H "9.$d (sysuser $u)"
  echo "admin_email: $(W 'option get admin_email')"
  echo "auto_update_core_minor: $(W 'option get auto_update_core_minor') / WP_AUTO_UPDATE_CORE: $(W 'config get WP_AUTO_UPDATE_CORE')"
  echo "auto_update_plugins: $(W 'option get auto_update_plugins --format=json')"
  echo "auto_update_themes: $(W 'option get auto_update_themes --format=json')"
  echo "-- plugins:"; W 'plugin list --fields=name,status,version,auto_update'
  echo "-- cron events:"; WPL 'cron event list --fields=hook,next_run_relative,recurrence' | grep -iE "hook|mail|notif|report|scan|digest|update|outbox|remind|integrity|wordfence|wf_|woocommerce|action_scheduler"
  echo "-- mu-plugins:"; ls $r/wp-content/mu-plugins/ 2>/dev/null; grep -lE "wp_mail|mail\(" $r/wp-content/mu-plugins/*.php 2>/dev/null
  if [ "$d" = cbcit.dk ]; then
    echo "-- Wordfence:"; W 'eval "global \$wpdb; foreach(\$wpdb->get_results(\"SELECT name,val FROM {\$wpdb->prefix}wfconfig WHERE name LIKE \\\"alert%\\\" OR name LIKE \\\"email%\\\" OR name LIKE \\\"schedule%\\\" OR name LIKE \\\"notification%\\\"\", ARRAY_A) as \$r){ echo \$r[\"name\"],\"=\",substr((string)\$r[\"val\"],0,120),\"\\n\"; }"'
    echo "-- WooCommerce:"; W 'option get woocommerce_stock_email_recipient'; W 'option get woocommerce_email_from_address'
    W 'eval "foreach([\"new_order\",\"cancelled_order\",\"failed_order\",\"low_stock\",\"no_stock\"] as \$k){ \$o=get_option(\"woocommerce_{\$k}_settings\"); echo \$k,\": \",(\$o[\"enabled\"]??\"?\"),\" -> \",(\$o[\"recipient\"]??\"-\"),\"\\n\"; }"'
    echo "-- Really Simple SSL mail:"; W 'option get rsssl_options --format=json' | grep -oiE '"[a-z_]*(mail|notif)[a-z_]*":[^,]*' | head
  fi
done

H "10. Egne logs, sidste 14 dage"
LIM=60 C 'tail -40 /var/log/cbc-egress-report.log 2>/dev/null'
LIM=60 C 'grep -hE "mail" /var/log/cbc-advisory-watch.log /var/log/cbc-security-updates.log /var/log/cbc-wp-integrity.log /var/log/cbc-backup-check.log 2>/dev/null | tail -40'
C 'cat /var/lib/cbc-advisory/last-report.txt 2>/dev/null | head -60'

H "11. Hardening-README (filliste + mail-omtale)"
C 'ls /root/cbc-hardening-2026-10/'
LIM=80 C 'grep -niE "mail|alarm|notif" /root/cbc-hardening-2026-10/README.md'

echo; echo "######## FÆRDIG $(date -Is)"
