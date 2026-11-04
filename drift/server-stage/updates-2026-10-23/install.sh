#!/usr/bin/env bash
# Installerer cbc-security-updates + cbc-advisory-watch (CBC 2026-10-23). Idempotent.
set -euo pipefail
S=/tmp/cbc-stage; H=/root/cbc-hardening-2026-10
mkdir -p "$H/backup" "$H/stage/updates-2026-10-23" /var/lib/cbc-advisory
[ -e "$H/backup/README.md.pre-updates-2026-10-23" ] || cp -a "$H/README.md" "$H/backup/README.md.pre-updates-2026-10-23"
install -m 750 -o root -g root "$S/cbc-security-updates.sh" /usr/local/sbin/cbc-security-updates.sh
install -m 750 -o root -g root "$S/cbc-advisory-watch.sh"   /usr/local/sbin/cbc-advisory-watch.sh
install -m 644 -o root -g root "$S/cron-cbc-security-updates" /etc/cron.d/cbc-security-updates
install -m 644 -o root -g root "$S/cron-cbc-advisory-watch"   /etc/cron.d/cbc-advisory-watch
install -m 644 -o root -g root "$S/logrotate-cbc-security-updates" /etc/logrotate.d/cbc-security-updates
cp -a "$S"/* "$H/stage/updates-2026-10-23/"
grep -q "^# Sikkerhedsopdateringer hver 4. time" "$H/README.md" || cat "$S/README-append.md" >> "$H/README.md"
echo "--- installeret:"; ls -la /usr/local/sbin/cbc-security-updates.sh /usr/local/sbin/cbc-advisory-watch.sh /etc/cron.d/cbc-security-updates /etc/cron.d/cbc-advisory-watch /etc/logrotate.d/cbc-security-updates
echo "--- logrotate-test:"; logrotate -d /etc/logrotate.d/cbc-security-updates 2>&1 | grep -iE "error|rotating pattern" | head -3 || true
echo "--- README:"; wc -l "$H/README.md"; grep -n "^# Sikkerhedsopdateringer" "$H/README.md"
