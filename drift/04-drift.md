# CBC Driftsdokumentation — 04 · Drift

> Deploy & release · cron/baggrundsjobs · mail (Brevo) · logs & overvågning.
> **Verificeret:** 2026-07-20 via live SSH (`crontab -l`, `wp cron event list`,
> `postconf -n`, log-inventory); **re-verificeret 2026-10-26** (crontabs, cron.d,
> systemd-timers, Postfix, mail-DNS). Detaljeret deploy-guide: se plugin-repoets
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
> **✅ Lukket okt. 2026 — alle tre sites kører system-cron:** `cbcitdk` og
> `datagaardendk` har hver en `*/5`-linje magen til events (512M) og
> `DISABLE_WP_CRON=true` i wp-config. WooCommerce Action Scheduler på cbcit.dk
> er dermed uafhængig af besøgstrafik.

### 2.2 CBC plugin-crons (verificeret schedulerede 2026-10-26, plugin 2.7.0)

| Hook | Frekvens | Kritikalitet |
|---|---|---|
| `cbc_outbox_send` | 5 min | 🔴 Sender kø-mails (publish + reminders) |
| `cbc_send_reminders` | Daglig | 🔴 Reminder-mails + PDF |
| `cbc_meeting_pending_reminder` | Daglig | 🟡 Rykker for ubesvarede mødeanmodninger |
| `cbc_pending_kollega_reminder` | Daglig | 🟡 Rykker for ventende kollega-godkendelser |
| `cbc_purge_expired_magic_tokens` | Daglig | 🟡 Oprydning af udløbne login-tokens |
| `cbc_reminder_pdf_purge` | Daglig | 🟢 Oprydning af genererede reminder-PDF'er |
| `cbc_outbox_purge` | Daglig | 🟢 Oprydning af sendt outbox |
| `cbc_event_log_purge` | Daglig | 🟢 Audit-log-oprydning |

Self-monitoring: plugin'et viser en rød **Cron-sundheds-banner** i wp-admin hvis
reminder-cron > 26 t eller outbox har hængende mails > 30 min (se `04-hosting §1`).

### 2.3 OS-/Plesk-/CBC-crons og timers

**CBC-egne jobs (root, siden okt. 2026 — alle dokumenteret med rollback i
`/root/cbc-hardening-2026-10/README.md`):**

| Job | Plan | Gør | Mail til johan@ |
|---|---|---|---|
| `/etc/cron.d/cbc-security-updates` → `cbc-security-updates.sh` | hver 4. t (:45) | Plesk-PHP + Ubuntu-security + cloudflared/Imunify via apt; genstarter FPM hvis pakken ikke gør | kun ved ændring eller fejl |
| `/etc/cron.d/cbc-advisory-watch` → `cbc-advisory-watch.sh check`/`weekly` | 07:15 dagligt / man 07:30 | PHP/WP/plugin/Plesk-versioner mod upstream; changelog-scan for sikkerheds-ord | ved afvigelse / altid mandag ("alt OK") |
| `/etc/cron.d/cbc-egress-report` → `cbc-egress-report.sh` | 06:55 dagligt | Opsummering af web-egress-drops | **altid** (udebleven mail = fejl) |
| `/etc/cron.d/cbc-woo-order-watch` → `cbc-woo-order-watch.sh` | hver time (:07) | > 5 WooCommerce-ordrer/time på cbcit.dk → alarm m. IP-fordeling | kun ved overskridelse |
| `cbc-wp-integrity.timer` → `cbc-wp-integrity.sh` | 05:15 dagligt | core+plugin-checksums alle 3 sites | kun ved afvigelse |
| `cbc-web-egress-refresh.timer` | hver time (+2 min efter boot) | Opløs allowlist-hostnavne → nft-sets | — |
| `cbc-web-egress-ranges.timer` | søn 04:50 | Hent Google/Meta-ranges | ved fejl |
| `cbc-fw-refresh.timer` | søn 04:30 | Opdatér CF-IP-sets i firewallen | ved ændring/fejl |
| sysuser-crontab event: `cbc-update-notify.php` | man 07:30 UTC | Ventende WP-opdateringer på event | kun hvis noget venter |
| **Johans PC:** Task Scheduler "CBC Hetzner ugentlig snapshot" | man 09:00 | Hetzner-snapshot (05 §1) | altid (OK/FEJL) |

**Plesk/OS:** `/etc/cron.d/plesk-backup-manager-task` (backup-poller hvert 15. min),
`imunify-*`, `plesk-outgoing-mail-statistics-poller`, `sysstat`, `e2scrub_all`;
`/etc/cron.daily/`: `50plesk-daily` (Plesk-autoupdate ~06:25), `dmarc-report`,
`logrotate`, `imunify-antivirus`, `webalizer` m.fl.; `psaadm`-crontab (WP Toolkit,
SSL It! `keep-secured.php` hver time = fornyer panel-certet, monitoring m.fl.).
Apt-timere flyttet til 01:00/02:00 (drop-ins), så de ikke kolliderer med Plesks
06:25-kørsel.

> **Alle alarm-mails går til `johan@cbcit.dk`** (cron, Imunify `ADMIN_CONTACTS`,
> Plesk-backup, snapshot). Ved overdragelse: skift til en fælles drifts-adresse
> ét sted ad gangen — listen ovenfor + 07 §10 er den komplette oversigt.

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

Det der **gælder udadtil** står i Cloudflare-zonen (01-fundament §4.4): `cbcit.dk`
SPF `-all` (lang legacy-liste), Brevo-DKIM `brevo1/brevo2`, DMARC **`p=none`**.
Plesks lokale BIND-zoner har egne SPF/DKIM/DMARC-records (`p=quarantine`), men de
besvares ikke udadtil og er kosmetiske. Plesk kører daglig DMARC-aggregate-rapport.
Status og åbne punkter pr. domæne (SPF-oprydning, DMARC for datagaarden.dk,
Brevo-autentificering af datagaarden.dk): tabellen i 01 §4.4.

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
(*"Mail service: Disabled for incoming mail"* — re-verificeret 2026-10-27;
`event.cbcit.dk` står på Enabled, hvilket er harmløst: subdomænet har ingen MX, og
Postfix lytter kun på loopback). Det er med vilje: en ny
subscription med mail-service tændt kaprer ellers MX/leveringen for `@cbcit.dk`.
**Enhver ny subscription skal have `plesk bin subscription -u <domain> -mail_service false`
(eller "Mail" fravalgt i UI) sat med det samme.**

---

## 4. Logs & overvågning

| Kilde | Sti / mekanisme |
|---|---|
| **Web-logs (pr. site)** | `/var/www/vhosts/system/<domæne>/logs/` — `access_ssl_log`, `error_log`, `proxy_access_log` (ægte klient-IP takket være CF-real-ip) |
| **PHP-fejl** | Plesk per-domæne `error_log` (samme mappe); mu-plugins logger `[cbc-checkout-guard]` dér |
| **Firewall egress-drops** | `journalctl -k | grep -E "egress-drop|cbc-egress-drop"` + daglig rapport-mail 06:55 |
| **fail2ban** | `fail2ban-client status <jail>` |
| **Malware** | Imunify (Plesk → Imunify-UI; `imunify360-agent malware on-demand list`) — dagligt 03:00 |
| **Patching/advisories** | `/var/log/cbc-security-updates.log`, `/var/log/cbc-advisory-watch.log` (+ `/var/lib/cbc-advisory/last-report.txt`), `/var/log/cbc-wp-integrity.log` |
| **Cloudflare** | Security → Events i dashboardet (Pro: 3 dages historik); GraphQL `firewallEventsAdaptive` via API-token (Analytics Read) |
| **App-selvmonitorering** | Cron-sundheds-banner i wp-admin (se §2.2) |
| **Backup-status** | Plesk Backup Manager + notifikations-mail til johan@; snapshot-mail fra Johans PC mandag |
| **Ekstern uptime** | **Ingen** (afklaret 2026-10-26). Al overvågning er selvrapporterende fra boksen — en angriber med root kan tie den. Anbefaling: ekstern dead-man/uptime-monitor (fx healthchecks.io-ping fra en cron + HTTP-check på de tre forsider). |

---

## 5. Verifikations-kommandoer

```bash
ssh cbc-prod 'for u in event.cbcit.dk_x3pjx5okzbn cbcitdk datagaardendk; do echo "-- $u"; crontab -l -u $u; done'
ssh cbc-prod "su -s /bin/bash event.cbcit.dk_x3pjx5okzbn -c '…/wp --path=…/httpdocs cron event list'"
ssh cbc-prod 'cat /etc/cron.d/cbc-*; systemctl list-timers --no-pager | grep cbc-'
ssh cbc-prod 'tail -5 /var/log/cbc-security-updates.log /var/log/cbc-advisory-watch.log /var/log/cbc-wp-integrity.log'
ssh cbc-prod 'postconf -n | grep -iE "relayhost|sasl|tls_security"; postconf -h inet_interfaces'
ssh cbc-prod 'plesk bin subscription --info cbcit.dk | grep -i "Mail service"'
```
