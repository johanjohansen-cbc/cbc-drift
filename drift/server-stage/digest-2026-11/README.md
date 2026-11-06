# Daglig driftsdigest — server.cbcit.dk (2026-11-06)

Mål: færre mails til johan@. Rutine-beskeder samles i **én daglig mail kl. 07:30**, og
kun det, der kræver handling nu, sendes straks som `[CBC ALARM] …`.
Grundlag: `00-live-inventar.md` (mail-inventaret fra samme dag, 128 mails på 14 dage).

Filerne i denne mappe har **samme stier som på serveren** (`usr/…`, `etc/…`).
`00-*` og `cbc-mail-inventar.sh`/`cbc-maillog-johan.sh` er det read-only inventar fra før ændringen.

## Arkitektur

```
CBC-scripts ──► cbc-notify.sh digest ──► /var/spool/cbc-digest/inbox ─┐
            └─► cbc-notify.sh alert  ──► sendmail straks [CBC ALARM]   │
                                                                       ├─► cbc-digest.sh 07:30 ──► ÉN mail
WP datagaarden / Plesk-backup / Imunify ──► digest@server.cbcit.dk     │      + live-status
   Postfix-alias → cbc-digest-ingest.sh (nobody) → ingest.php ─────────┘      → archive/YYYY-MM-DD (30 d)
         emne matcher /etc/cbc-digest-alert-patterns                          → healthchecks "digest"
         └─► /var/spool/cbc-digest/outbox ─► cbc-digest-alert.path/.service (root) ─► cbc-notify.sh alert
```

`nobody` må ikke sende mail selv, fordi Plesks sendmail-wrapper (`limit-out`) afviser systembrugere.
Derfor går alarmer fra aliaset via outbox og en root-service. Kontrollen er bevaret, ikke omgået.

## Filer på serveren

| Fil | Mode | Rolle |
|---|---|---|
| `/usr/local/sbin/cbc-notify.sh` | 755 root | Fælles afsender: `digest` → spool, `alert` → straks. Rollback-kontakt indbygget |
| `/usr/local/sbin/cbc-digest.sh` | 755 root | Daglig digest (`--test`, `--dry-run`) |
| `/usr/local/sbin/cbc-digest-ingest.sh` | 755 root | Postfix-pipe for `digest@` (kører som nobody) |
| `/usr/local/sbin/cbc-digest-alert.sh` | 755 root | Tømmer outbox → straks-alarmer |
| `/usr/local/lib/cbc-digest/ingest.php` | 644 | MIME-parser + alarm-mønster (Plesk PHP-CLI) |
| `/usr/local/lib/cbc-digest/wp-status.php` | 644 | Read-only WP-status (WP-cron, event outbox, `Cron_Health_Notice`) som sysuser |
| `/etc/cbc-digest-alert-patterns` | 644 | Regex pr. linje på **emnet** → straks-alarm |
| `/etc/cron.d/cbc-digest` | 644 | 07:30 dagligt |
| `/etc/systemd/system/cbc-digest-alert.{path,service}` | 644 | `DirectoryNotEmpty=/var/spool/cbc-digest/outbox` |
| `/etc/logrotate.d/cbc-digest` | 644 | cbc-digest.log, cbc-woo-order-watch.log, cbc-hc-ping.log |
| `/var/spool/cbc-digest/` | 0710 root:nogroup | `inbox/` + `outbox/` 1730 root:nogroup (nobody kan oprette, ikke læse/slette), `archive/` 0700 |
| `/etc/aliases` | +1 linje | `digest: "|/usr/local/sbin/cbc-digest-ingest.sh"` |
| `/etc/postfix/main.cf` | ændret | `mydestination` += `server.cbcit.dk` |
| `/etc/cbc-healthchecks.conf` | +1 kommentar | `# digest=` TODO (Johan opretter checket) |

**Ændrede scripts** (kun send-funktionen; diff mod `/root/cbc-hardening-2026-10/pre-digest-20261106/`):

| Script | Digest | Straks (`[CBC ALARM]`) |
|---|---|---|
| `cbc-egress-report.sh` | daglig rapport | — |
| `cbc-advisory-watch.sh` | `check` uden sikkerhedsflag, `weekly` | `check` med `[SIKKERHED?`-afvigelse |
| `cbc-security-updates.sh` | opgradering OK | fejl, FPM ikke aktiv, site ≠ HTTP 200, `--test-mail` |
| `cbc-fw-refresh.sh` | CF-IP-liste ændret | refresh fejlede |
| `cbc-web-egress-ranges-fetch.sh` | — | fejl |
| `cbc-wp-integrity.sh` | kun ventende opdateringer | checksum-afvigelse |
| `cbc-woo-order-watch.sh` | — | > 5 ordrer/time (uændret adfærd) |

**Cron-ændringer:** `cbc-advisory-watch` weekly flyttet fra man 07:30 til 07:15 (så ugerapporten
når digesten). `cbc-woo-order-watch` og `cbc-hc-ping.sh` i egress-linjen skriver nu til log
(`>> /var/log/cbc-woo-order-watch.log` / `cbc-hc-ping.log`) i stedet for at give cron-mail til root.

**Modtagere flyttet til `digest@server.cbcit.dk`:** Plesk planlagt backup, Imunify `ADMIN_CONTACTS`,
datagaarden.dk WP `admin_email`. **Ikke flyttet med vilje:** event.cbcit.dk og cbcit.dk `admin_email`
og Plesk panel-`admin_email` (begrundelse i `04-drift.md` §2.3).

**Andre ændringer samme dag (quick wins):** event.cbcit.dk WP 7.1.3 → 7.1.4 (dump
`/var/backups/cbc-pre-deploy/pre-wp714-20261106-120038.sql.gz`); Imunify-scan månedlig → dagligt 03:00;
Wordfence-støj slået fra (tabel nedenfor); `/etc/cron.d/cbc-egress-report.pre-hc-20261104` flyttet til
`/root/cbc-hardening-2026-10/`. cbcit.dk-plugins webappick 8.0.42 / turnstile 1.44.5 var allerede
opdateret af WP-autoupdate 08:08. Site Kit email-reporting på datagaarden har ingen abonnenter (intet sendes).

| Wordfence-nøgle | cbcit.dk | datagaarden.dk |
|---|---|---|
| `alertOn_lostPasswdForm` | 1 → 0 | 1 → 0 |
| `email_summary_enabled` (ugentligt resumé) | 1 → 0 | 1 → 0 |
| `alertOn_block` (hver IP-blokering) | 0 (uændret) | 1 → 0 |
| `alertOn_update` | 0 (uændret) | 0 (uændret) |
| critical / scanIssues / adminLogin / breachLogin / loginLockout / wafAlertOnAttacks | uændret (1) | uændret (1) |

## Installation (som udført 2026-11-06)

```bash
S=/root/cbc-hardening-2026-10/digest-2026-11-stage   # kopi af denne mappe
B=/root/cbc-hardening-2026-10/pre-digest-20261106    # cp -a-backup af alle berørte filer
install -m 755 $S/usr/local/sbin/cbc-{notify,digest,digest-ingest,digest-alert}.sh /usr/local/sbin/
install -d -m 755 /usr/local/lib/cbc-digest && install -m 644 $S/usr/local/lib/cbc-digest/*.php /usr/local/lib/cbc-digest/
install -m 644 $S/etc/cbc-digest-alert-patterns /etc/ ; install -m 644 $S/etc/logrotate.d/cbc-digest /etc/logrotate.d/
install -d -o root -g nogroup -m 0710 /var/spool/cbc-digest
install -d -o root -g nogroup -m 1730 /var/spool/cbc-digest/inbox /var/spool/cbc-digest/outbox
install -d -m 0700 /var/spool/cbc-digest/archive
postconf -e "mydestination = localhost.cbcit.dk, localhost, localhost.localdomain, server.cbcit.dk"
echo 'digest: "|/usr/local/sbin/cbc-digest-ingest.sh"' >> /etc/aliases && newaliases && postfix check && postfix reload
install -m 644 $S/etc/systemd/system/cbc-digest-alert.* /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now cbc-digest-alert.path
install -m 755 $S/usr/local/sbin/cbc-{egress-report,advisory-watch,security-updates,fw-refresh,web-egress-ranges-fetch,wp-integrity,woo-order-watch}.sh /usr/local/sbin/
install -m 644 $S/etc/cron.d/cbc-{digest,advisory-watch,egress-report,woo-order-watch} /etc/cron.d/
```

## Test

```bash
echo hej | cbc-notify.sh digest "test" notify-test            # → fil i inbox
printf 'Subject: test FAILED\n\nx\n' | sendmail digest@server.cbcit.dk   # → [CBC ALARM] straks + i digest
cbc-digest.sh --dry-run > /tmp/d.html                          # se HTML uden at sende
cbc-digest.sh --test                                           # send nu, arkiverer ikke
journalctl -t cbc-digest-ingest --since -1h ; tail /var/log/cbc-digest.log ; grep 'to=<johan@' /var/log/maillog | tail
```

## Rollback

**Hurtig (bevarer alt, sender straks igen):** `touch /etc/cbc-digest.disabled`. Så sender
`cbc-notify.sh` digest-beskeder straks (uden præfiks), og aliaset videresender alt straks via outbox.
Det, der allerede ligger i spoolen, kommer med i næste 07:30-digest.

**Fuld:**
```bash
B=/root/cbc-hardening-2026-10/pre-digest-20261106
for f in cbc-egress-report.sh cbc-advisory-watch.sh cbc-security-updates.sh cbc-fw-refresh.sh \
         cbc-web-egress-ranges-fetch.sh cbc-wp-integrity.sh cbc-woo-order-watch.sh; do cp -a $B/$f /usr/local/sbin/; done
cp -a $B/cbc-woo-order-watch $B/cbc-egress-report $B/cbc-advisory-watch /etc/cron.d/
rm -f /etc/cron.d/cbc-digest
# modtagere tilbage til johan@:
MYSQL_PWD=$(cat /etc/psa/.psa.shadow) mysql -uadmin psa -e "UPDATE BackupsScheduled SET email='johan@cbcit.dk' WHERE id=1"
imunify360-agent config update '{"ADMIN_CONTACTS": {"emails": ["johan@cbcit.dk"]}}'
su -s /bin/bash datagaardendk -c "/opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp --path=/var/www/vhosts/datagaarden.dk/httpdocs --skip-themes option update admin_email johan@cbcit.dk"
# Postfix:
cp -a $B/aliases /etc/aliases && newaliases
postconf -e "mydestination = localhost.cbcit.dk, localhost, localhost.localdomain" && postfix check && postfix reload
systemctl disable --now cbc-digest-alert.path
# (cbc-notify/digest/ingest-filerne kan blive liggende uden effekt)
```
Imunify-scan tilbage til månedlig: `imunify360-agent config update '{"MALWARE_SCAN_SCHEDULE":{"interval":"month","day_of_month":28,"hour":3}}'`.
Wordfence: sæt nøglerne i tabellen ovenfor tilbage med `wfConfig::set('<nøgle>', 1)` via `wp eval-file` som sysuser.

## Kendte begrænsninger

- Healthchecks-status kan ikke læses uden API-nøgle. Digesten viser kun hvilke checks der pinges.
- Advisory-rapporten i digesten er den fra 07:15 og kan være forældet, hvis der er rettet noget siden.
- Plesk kan i sjældne tilfælde regenerere `main.cf`. Digesten advarer, hvis `server.cbcit.dk` mangler i `mydestination`.
- Ingest matcher kun **emnet** mod alarm-mønstrene. En kritisk besked med harmløst emne havner i digesten.
