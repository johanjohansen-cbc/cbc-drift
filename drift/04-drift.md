# CBC Driftsdokumentation — 04 · Drift

> Deploy & release · cron/baggrundsjobs · mail (Brevo) · logs & overvågning.
> **Verificeret:** 2026-07-20 via live SSH (`crontab -l`, `wp cron event list`,
> `postconf -n`, log-inventory). Detaljeret deploy-guide: se plugin-repoets
> `docs/05-deploy-workflow.md` (denne fil opsummerer + krydsrefererer).

---

## 1. Deploy & release

### 1.1 Model

Kode deployes via **selvhostede bare git-repos** på serveren — ikke via SFTP,
ikke via GitHub-as-source. GitHub er kun et privat **mirror** (redundans).

| Repo | Bare repo på server | Arbejdskopi | Deploy-script |
|---|---|---|---|
| Plugin | `/var/git/cbc-event-planner.git` | `…/plugins/cbc-event-planner/` | `deploy.sh` |
| Tema | `/var/git/cbc-child.git` | `…/themes/cbc-child/` | `deploy-theme.sh` |

Remotes på laptop (pr. repo): `prod` (bare repo), `github` (mirror), **`both`**
(pusher til begge på én gang — bare repo først, så GitHub).

### 1.2 Standard-flow

```bash
# --- LOCAL (laptop, i repo-mappen) ---
git add . && git commit -m "…"          # + evt. git tag -a vX.Y.Z
git push both main                       # → prod bare repo + GitHub-mirror
git push both --tags                     # hvis tagget

# --- SERVER (via SSH som root) ---
ssh cbc-prod
/var/www/vhosts/event.cbcit.dk/httpdocs/wp-content/themes/cbc-child/deploy-theme.sh   # tema FØRST
/var/www/vhosts/event.cbcit.dk/httpdocs/wp-content/plugins/cbc-event-planner/deploy.sh # så plugin
```

**Rækkefølge:** tema før plugin (så plugin-kode altid finder nyeste tema-markup).

### 1.3 Hvad deploy-scripts gør

Begge: krav-tjek (root) → pre-deploy backup (se 05) → `git pull --ff-only` →
**chown tilbage til sysuser + normalisér web-perms (755/644)** → (plugin også:
`wp cbc db migrate`) → **`systemctl reload plesk-php84-fpm`** (rydder opcache —
kritisk) → post-deploy-verifikation. Scriptet printer den eksakte rollback-kommando
ved hver kørsel. Exit-koder: `0`=ok · `1`=krav · `2`=git · `4`=wp-cli · `5`=fpm/verifikation.

> **Vigtigt:** `wp` køres altid som sysuser med `-d memory_limit=512M` (default 128M
> OOM'er på tunge kald). Kør ALDRIG `wp` som root mod sitet (skaber root-ejede
> cache-filer → perms-brud).

### 1.4 Rollback (kort)

```bash
ssh cbc-prod
cd …/plugins/cbc-event-planner
git checkout <forrige-ref>
chown -R event.cbcit.dk_x3pjx5okzbn:psaserv .   # tema: chown --reference=../twentytwentyfive
systemctl reload plesk-php84-fpm
```
Fuld rollback + DB-restore: se `docs/05-deploy-workflow.md §10`.

---

## 2. Cron & baggrundsjobs

### 2.1 WordPress-cron (system-drevet)

WP's egen request-cron er slået fra (`DISABLE_WP_CRON=true`). I stedet kører
**sysuser-crontabben** (`event.cbcit.dk_x3pjx5okzbn`):

```cron
*/5 * * * *  …/php8.4 …/wp --path=…/event.cbcit.dk/httpdocs cron event run --due-now >/dev/null 2>&1
30 7 * * 1   …/php8.4 -d memory_limit=512M …/wp … eval-file …/cbc-update-notify.php   # ugentligt update-tjek
```

> **✅ Lukket 2026-07-20:** `*/5`-linjen har nu `-d memory_limit=512M` (tidligere
> åben forbedring fra 04-hosting-checklist §1 — default 128M kunne OOM'e en tung
> `cbc_send_reminders`-kørsel). Crontab-backup fra før ændringen:
> `/root/crontab-backup-2026-07-20-*.txt`.
>
> **⚠️ Åbent — cbcit.dk har INGEN system-cron:** `cbcitdk` har ingen crontab og
> `DISABLE_WP_CRON` er ikke sat → WooCommerce's Action Scheduler kører kun ved
> besøgstrafik. Overvej at spejle event-mønstret (system-cron + DISABLE_WP_CRON)
> for cbcit.dk. Husk `-d memory_limit=512M` — WP-CLI OOM'er ellers på det site.

### 2.2 CBC plugin-crons (verificeret schedulerede 2026-07-20)

| Hook | Frekvens | Kritikalitet |
|---|---|---|
| `cbc_outbox_send` | 5 min | 🔴 Sender kø-mails (publish + reminders) |
| `cbc_send_reminders` | Daglig | 🔴 Reminder-mails + PDF |
| `cbc_purge_expired_magic_tokens` | Daglig | 🟡 Oprydning af udløbne login-tokens |
| `cbc_outbox_purge` | Daglig | 🟢 Oprydning af sendt outbox |
| `cbc_event_log_purge` | Daglig | 🟢 Audit-log-oprydning |

Self-monitoring: plugin'et viser en rød **Cron-sundheds-banner** i wp-admin hvis
reminder-cron > 26 t eller outbox har hængende mails > 30 min (se `04-hosting §1`).

### 2.3 OS-/Plesk-crons

- `/etc/cron.d/`: `plesk-backup-manager-task` (backup-poller hvert 15. min),
  `imunify-*` (malware-scan), `plesk-outgoing-mail-statistics-poller`, `sysstat`.
- `/etc/cron.daily/`: `50plesk-daily`, **`dmarc-report`** (Plesk DMARC aggregate),
  `logrotate`, `imunify-antivirus`, `webalizer`, m.fl.

---

## 3. Mail (udgående via Brevo)

### 3.1 Transport

Al udgående mail relayes gennem **Brevo** (verificeret `postconf -n`):

```
relayhost = [smtp-relay.brevo.com]:587
smtp_sasl_auth_enable = yes            # SASL-login → Brevo (credentials: /etc/postfix/sasl_passwd → 07)
smtp_tls_security_level = encrypt
```

Flow: `wp_mail()` (plugin `Email\Mailer` → `Layout::wrap`) → PHP `mail()` →
Postfix → Brevo → modtager. `/etc/mailname` = `server.cbcit.dk`. CBC-afsendere:
options `cbc_contact_email` / `cbc_noreply_email`.

### 3.2 Autentificering (SPF/DKIM/DMARC)

Sat pr. domæne (se 01-fundament §4.4): SPF `-all`, DKIM `default._domainkey`,
DMARC `p=quarantine` (strict alignment). Plesk kører daglig DMARC-aggregate-rapport.

> **✅ Deliverability-test gennemført 2026-07-20 (mail-tester.com): 7,6/10 —
> "properly authenticated": SPF ✓ DKIM ✓ DMARC ✓**, ikke blocklisted. Brevo
> DKIM-signerer korrekt (nøglerne `brevo1/brevo2._domainkey.cbcit.dk` i CF-zonen);
> afsender er `noreply@cbcit.dk` (option `cbc_noreply_email`). Fradragene (-1,9
> SpamAssassin / -0,5 body) skyldtes overvejende testmailens rå indhold uden
> `Email\Layout::wrap`-templaten — ikke transporten. **Restpunkter (lav prioritet):**
> `_dmarc.cbcit.dk` står på `p=none` (kun monitorering — overvej `p=quarantine`
> efter en periode med rene DMARC-rapporter); SPF-recorden er en lang legacy-liste
> der kan trimmes. Re-test efter enhver ændring i mail-DNS.

### 3.3 Mail-kaprings-invariant (KRITISK)

`cbcit.dk` og `datagaarden.dk` har **incoming mail slået fra**
(*"Mail service: Disabled for incoming mail"*). Det er med vilje: en ny
subscription med mail-service tændt kaprer ellers MX/leveringen for `@cbcit.dk`.
**Enhver ny subscription skal have `plesk bin subscription -u <domain> -mail_service false`
(eller "Mail" fravalgt i UI) sat med det samme.**

---

## 4. Logs & overvågning

| Kilde | Sti / mekanisme |
|---|---|
| **Web-logs (event)** | `/var/www/vhosts/event.cbcit.dk/logs/` — `access_ssl_log`, `error_log`, `proxy_access_log` |
| **PHP-fejl** | Plesk per-domæne error_log (samme mappe) + `/var/log/` |
| **Firewall egress-drops** | `journalctl -k | grep cbc_fw` |
| **fail2ban** | `fail2ban-client status <jail>` |
| **Malware** | Imunify (Plesk → Imunify-UI) |
| **App-selvmonitorering** | Cron-sundheds-banner i wp-admin (se §2.2) |
| **Backup-status** | Plesk Backup Manager + notifikations-mail til johan@ |
| **Ekstern uptime** | ‹UDFYLD: er der en ekstern uptime-monitor (UptimeRobot e.l.)? Hvis nej — overvej én, der pinger event.cbcit.dk og alarmerer.› |

---

## 5. Verifikations-kommandoer

```bash
ssh cbc-prod 'crontab -l -u event.cbcit.dk_x3pjx5okzbn'
ssh cbc-prod "su -s /bin/bash event.cbcit.dk_x3pjx5okzbn -c '…/wp --path=…/httpdocs cron event list'"
ssh cbc-prod 'postconf -n | grep -iE "relayhost|sasl|tls_security"'
ssh cbc-prod 'plesk bin subscription --info cbcit.dk | grep -i "Mail service"'
```
