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

**Siden 2026-11-06 sender ingen CBC-script mail direkte.** Alt går gennem
`/usr/local/sbin/cbc-notify.sh <digest|alert> "<emne>" [job]` (afsender `CBC Drift <noreply@cbcit.dk>`):
**alert** = straks, emne `[CBC ALARM] …`; **digest** = spoolet i `/var/spool/cbc-digest/inbox` og
samlet i **én daglig digest-mail 07:30** (`cbc-digest.sh`, se tabellen og §4). Detaljer, filer
og rollback: `server-stage/digest-2026-11/README.md`.

| Job | Plan | Gør | Mail til johan@ (digest / akut) |
|---|---|---|---|
| `/etc/cron.d/cbc-digest` → `cbc-digest.sh` (siden 2026-11-06) | 07:30 dagligt | Samler spool + live-status (backup, opdateringer, sikkerhed, sites, server) i én HTML-mail; arkiverer spool (30 dage); pinger healthchecks.io (`digest`, §4) | **altid** (én mail/dag, "Alt grønt" / "N punkter kræver opmærksomhed") |
| `/etc/cron.d/cbc-security-updates` → `cbc-security-updates.sh` | hver 4. t (:45) | Plesk-PHP + Ubuntu-security + cloudflared/Imunify via apt; genstarter FPM hvis pakken ikke gør | opgradering OK → digest · fejl / FPM nede / site ≠ 200 → **akut** |
| `/etc/cron.d/cbc-advisory-watch` → `cbc-advisory-watch.sh check`/`weekly` | 07:15 dagligt (også mandag `weekly`, flyttet fra 07:30 2026-11-06) | PHP/WP/plugin/Plesk-versioner mod upstream; changelog-scan for sikkerheds-ord | afvigelse → digest · afvigelse med `[SIKKERHED?` → **akut** · weekly → digest (fuld længde mandag) |
| `/etc/cron.d/cbc-egress-report` → `cbc-egress-report.sh` | 06:55 dagligt | Opsummering af web-egress-drops; pinger derefter healthchecks.io (`egress`, §4) | **altid** → digest (udebleven kørsel = healthchecks-alarm) |
| `/etc/cron.d/cbc-backup-check` → `cbc-backup-check.sh` (siden 2026-11-04) | 06:40 dagligt | Tjekker at nattens Plesk-backup er < 26 t gammel, `status_OK` + `dumpresult_SUCCESS` og sendt til OneDrive; pinger healthchecks.io (`backup`, OK eller `/fail`). `-n` = kun tjek (bruges også af digesten) | — (alarm fra healthchecks.io; status i digest) |
| `/etc/cron.d/cbc-woo-order-watch` → `cbc-woo-order-watch.sh` | hver time (:07) | > 5 WooCommerce-ordrer/time på cbcit.dk → alarm m. IP-fordeling. Output → `/var/log/cbc-woo-order-watch.log` | **akut** ved overskridelse |
| `cbc-wp-integrity.timer` → `cbc-wp-integrity.sh` | 05:17 dagligt | core+plugin-checksums alle 3 sites | checksum-afvigelse → **akut** · kun ventende opdateringer → digest |
| `cbc-web-egress-refresh.timer` | hver time (+2 min efter boot) | Opløs allowlist-hostnavne → nft-sets | — |
| `cbc-web-egress-ranges.timer` | søn 04:50 | Hent Google/Meta-ranges | fejl → **akut** |
| `cbc-fw-refresh.timer` | søn 04:30 | Opdatér CF-IP-sets i firewallen | ændring → digest · fejl → **akut** |
| `cbc-digest-alert.path` → `cbc-digest-alert.sh` (siden 2026-11-06) | ved fil i `/var/spool/cbc-digest/outbox` | Sender alarmer fra `digest@`-aliaset straks som root (Postfix-pipen kører som `nobody`, som Plesk `limit-out` ikke tillader at sende) | **akut** |
| sysuser-crontab event: `cbc-update-notify.php` | man 07:30 (server-tid CET, ikke UTC) | Ventende WP-opdateringer på event | direkte til event's admin_email (johan@), kun hvis noget venter |
| **Johans PC:** Task Scheduler "CBC Hetzner ugentlig snapshot" | man 09:00 | Hetzner-snapshot (05 §1); pinger healthchecks.io (`snapshot`, OK eller `/fail`) siden 2026-11-04 | altid (OK/FEJL), direkte |

**`digest@server.cbcit.dk` (siden 2026-11-06):** Postfix-alias i `/etc/aliases` →
`|/usr/local/sbin/cbc-digest-ingest.sh` (`server.cbcit.dk` er tilføjet `mydestination`).
Mails dertil parses (emne + tekstdel) og havner i digesten; emner der matcher
`/etc/cbc-digest-alert-patterns` (fail/error/malware/kritisk/kunne ikke/advarsel/anmodning …)
sendes **straks** som `[CBC ALARM]`. Disse kilder peger nu på aliaset:

| Kilde | Før | Nu |
|---|---|---|
| Plesk planlagt backup (`psa.BackupsScheduled.email`, id 1) | johan@ | digest@ |
| Imunify `ADMIN_CONTACTS` | johan@ | digest@ (malware-fund matcher alarm-mønster → straks) |
| datagaarden.dk WP `admin_email` | johan@ | digest@ (autoupdate-rapporter m.m.; kontaktformular → salg@ og nyhedsbrev → johan@ er uberørt) |
| **event.cbcit.dk WP `admin_email`** | johan@ | **uændret med vilje**: pluginet viser den som `system.support_email` i deltager-mails |
| **cbcit.dk WP `admin_email`** | johan@ | **uændret med vilje**: WooCommerce `failed_order` har ingen egen modtager → admin_email (card-testing-signal) |
| Plesk panel-`admin_email` (+ autoupdate-/health-notifikationer) | johan@ | **uændret**: er også Plesk-admin-kontakt; ændres kun bevidst i UI |

**Støjreduktion samme dag:** Wordfence (cbcit.dk + datagaarden.dk) `alertOn_lostPasswdForm`
1→0 og ugentligt `email_summary_enabled` 1→0; datagaarden også `alertOn_block` 1→0.
Kritiske fund, scan-issues, admin-login og angrebstærskel er fortsat slået til
(`alertEmails` = johan@, direkte). Imunify-scan sat til **dagligt 03:00** (stod på
månedlig d. 28 — afveg fra docs).

**Plesk/OS:** `/etc/cron.d/plesk-backup-manager-task` (backup-poller hvert 15. min),
`imunify-*`, `plesk-outgoing-mail-statistics-poller`, `sysstat`, `e2scrub_all`;
`/etc/cron.daily/`: `50plesk-daily` (Plesk-autoupdate ~06:25), `dmarc-report`,
`logrotate`, `imunify-antivirus`, `webalizer` m.fl.; `psaadm`-crontab (WP Toolkit,
SSL It! `keep-secured.php` hver time = fornyer panel-certet, monitoring m.fl.).
Apt-timere flyttet til 01:00/02:00 (drop-ins), så de ikke kolliderer med Plesks
06:25-kørsel.

> **Alle alarm-mails går til `johan@cbcit.dk`** (CBC-scripts via `cbc-notify.sh`,
> digest-aliaset, snapshot, healthchecks.io, UptimeRobot, Wordfence). **Besluttet 2026-11-05
> (sikkerhedsplan Fase 5 pkt 10): ingen fælles drift@-liste.** Jan har adgang til
> Johans indbakke og får en opgave om at tjekke den ved Johans fravær. Ved
> overdragelse: skift adressen ét sted ad gangen — listen ovenfor + 07 §10 er
> den komplette oversigt.

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

**Server-scripts (siden 2026-11-06):** ensrettet afsender `CBC Drift <noreply@cbcit.dk>`
(envelope `-f noreply@cbcit.dk`) via `cbc-notify.sh`/`cbc-digest.sh` — før havde de fire
forskellige From (bl.a. ingen From → root@server.cbcit.dk). Relevant for DMARC-skridtet
til `p=quarantine` (§3.2). `server.cbcit.dk` er nu i `mydestination`, så mail til
`…@server.cbcit.dk` leveres lokalt (aliaset `digest`, root → lokal mailbox) i stedet for
at blive relayet til Brevo. **Plesk sendmail-wrapperen (`/usr/sbin/sendmail` →
`postfix-sendmail-wrapper`) afviser systembrugere som `nobody` (`limit-out`).**
Postfix-log: `/var/log/maillog` (+ `maillog.processed`).

### 3.2 Autentificering (SPF/DKIM/DMARC)

Det der **gælder udadtil** står i Cloudflare-zonen (01-fundament §4.4): `cbcit.dk`
SPF `-all` (ryddet 2026-10-29: MS365 + Mailchimp + `a:spf1.kobalt.dk`), Brevo-DKIM `brevo1/brevo2`, DMARC **`p=none`**.
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
> efter en periode med rene DMARC-rapporter — og først efter header-test af
> server-cron-mails). SPF-recorden blev trimmet 2026-10-29 (01 §4.4).
> Re-test efter enhver ændring i mail-DNS.

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
| **Daglig digest (siden 2026-11-06)** | Én mail 07:30 til johan@ fra `cbc-digest.sh`: statusbjælke + Backup · Opdateringer og patching · Sikkerhed · Sites (HTTP via origin, WP-cron, event outbox + `Cron_Health_Notice`) · Server · Øvrige meddelelser. Spool `/var/spool/cbc-digest/{inbox,outbox,archive}`, log `/var/log/cbc-digest.log`, ingest-log i syslog (`cbc-digest-ingest`). `cbc-digest.sh --test` = send nu uden at arkivere; `--dry-run` = HTML til stdout. **Rollback-kontakt: `touch /etc/cbc-digest.disabled`** (alt sendes straks igen). |
| **Mail-log** | `/var/log/maillog` (+ `maillog.processed`) — `grep "to=<johan@cbcit.dk>"` |
| **Backup-status** | Plesk Backup Manager + notifikation til digest@ (fejl/advarsel → straks som alarm); status i daglig digest; snapshot-mail fra Johans PC mandag |
| **Ekstern uptime** | **UptimeRobot** (HTTP-oppetid på sitene; alarm til johan@ — konto/login → 07). Oplyst 2026-11-04; tjek at alle tre forsider + `plesk-event.cbcit.dk` er med. |
| **Ekstern dead-man (healthchecks.io, siden 2026-11-04)** | Fire checks, alarm til johan@ ved udebleven ping (login → 07): **`egress`** (periode 1 d, grace 1 t) fra `cbc-egress-report`-cron; **`backup`** (1 d / 2 t) fra `cbc-backup-check.sh` 06:40; **`snapshot`** (7 d / 1 d) fra `hetzner-snapshot.ps1` på Johans PC. **`digest`** (1 d / 2 t) fra `cbc-digest.sh` 07:30 (aktiv siden 2026-11-06). Server-siden: `/usr/local/sbin/cbc-hc-ping.sh <navn> [rc]` læser URL'er fra `/etc/cbc-healthchecks.conf` (600 root, ikke i git); `rc≠0` → `/fail`-ping = straks-alarm. Rollback + detaljer: `/root/cbc-hardening-2026-10/README.md` (2026-11-04). Dermed er det selvrapporterende hul fra audit 26/10 lukket for de fire vigtigste jobs; de øvrige cron-mails er stadig kun selvrapporterende. |

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
