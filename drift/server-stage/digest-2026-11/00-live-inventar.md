# Mail-inventar til johan@cbcit.dk — live-verifikation

> Kilde: `00-live-inventar.txt` = read-only kørsel af `cbc-mail-inventar.sh` mod
> `cbc-prod` (server.cbcit.dk), **2026-11-06 11:24–11:24:42 CET**, komplet (slutter
> med FÆRDIG). Secret-filteret er tjekket: ingen passwords, tokens, SASL-linjer eller
> healthchecks-URL'er i outputtet. Ikke committet.
>
> **Postfix-optælling:** sektion 3 i inventaret talte 0 mails, fordi scriptet greppede
> `/var/log/mail.log*`. Plesk logger til `/var/log/maillog` + `maillog.processed`.
> Tallene er derfor hentet med `cbc-maillog-johan.sh` → `00-maillog-johan.txt` og et
> supplerende kald med oprindelig afsender → `00-maillog-johan-origin.txt`. Begge er
> read-only og kørt 2026-11-06 ca. 11:35. Se tabellen nederst.

## Live-sektioner 1–11

**1. Cron/timers.** Seks CBC-cron.d-filer: advisory-watch (07:15 alle dage undtagen mandag + mandag 07:30), backup-check 06:40, egress-report 06:55 (+ `cbc-hc-ping.sh egress $?`), security-updates :45 hver 4. time, woo-order-watch :07 hver time. Desuden ligger **`cbc-egress-report.pre-hc-20261104`** (backup fra før healthchecks) i `/etc/cron.d`. Debian-cron springer filnavne med punktum over, så den kører sandsynligvis ikke, men den hører ikke hjemme der. Timere: wp-integrity (05:17), web-egress-refresh (hver time), fw-refresh og web-egress-ranges (søn ~04:36/04:57), apt-daily 01:01, apt-daily-upgrade 02:29. Sysuser-crontabs: `*/5` WP-cron på alle tre sites; event har også `cbc-update-notify.php` man 07:30. `psaadm` har `MAILTO=""`. Root har ingen crontab.

**2. Mail-afsendere i egne scripts.** Syv scripts sender via `/usr/sbin/sendmail -t`, alle til johan@: advisory-watch (From `cbc-advisory-watch@server.cbcit.dk`), security-updates (`cbc-security-updates@server.cbcit.dk`), wp-integrity (From **`noreply@cbcit.dk`**), samt egress-report, fw-refresh, web-egress-ranges-fetch og woo-order-watch (**ingen From** → root@server.cbcit.dk, omskrevet via `sender_canonical`). `dmarc-report` (cron.daily) kører Plesks `dmarc_aggregate_report`. `s-nail` er installeret, logwatch er ikke.

**3. Postfix.** Relay `[smtp-relay.brevo.com]:587`, TLS `encrypt`, `inet_interfaces = loopback-only`, `myorigin = /etc/mailname` (server.cbcit.dk), `sender_canonical_maps` (regexp, 49 bytes). Plesk-milter og canonical-tcp-maps er aktive. `/etc/aliases` har kun `postmaster: root`, så root har intet alias. SASL-linjerne er bevidst filtreret fra, så `smtp_sasl_auth_enable` kunne hverken be- eller afkræftes. Loggen ligger i `/var/log/maillog` (5,9 KB, nyroteret) og `maillog.processed` (6,4 MB).

**4. Plesk-notifikationer.** Backup: daglig, rotation 30, OneDrive, `email: johan@cbcit.dk`. Admin-mail og `autoupdates-email-notification` er begge johan@. Tabellen `Notifications` er tom, så Plesk bruger standardopsætningen. Sqlite-filerne for log-browser, sslit og one-drive-backup indeholder johan@. `misc`-forespørgslen fejlede (forkert kolonnenavn), og der er ikke hentet mere herfra.

**5. Imunify360.** `ADMIN_CONTACTS = johan@cbcit.dk` med `enable_icontact_notifications` slået til. `notify_on_detect` er slået til. Notifikations-scriptet kører ved REALTIME-, USER_SCAN- og CUSTOM_SCAN_MALWARE_FOUND. **`MALWARE_SCAN_SCHEDULE = month, dag 28, kl. 03`** (se Afvigelser). ERROR_REPORTING og SEND_ADDITIONAL_DATA er slået til (de sender data til CloudLinux, ikke mail).

**6. unattended-upgrades.** Ingen `Mail`-direktiver, så der kommer ingen apt-mails. `52cbc-auto-reboot`: Automatic-Reboot `true`, 04:00. Ingen reboot afventer.

**7. fail2ban.** `destemail = johan@cbcit.dk` er sat, men alle actions er rene `iptables*` uden mail-action, så fail2ban sender reelt ingen mail. 13 jails er aktive.

**8. Sites/sysusers.** event.cbcit.dk → `event.cbcit.dk_x3pjx5okzbn`, cbcit.dk → `cbcitdk`, datagaarden.dk → `datagaardendk`.

**9. WordPress.**
- **event:** admin_email johan@, kun minor-core-autoupdate og ingen plugin-autoupdates (cbc-event-planner 2.7.0, two-factor, duplicate-post). Plugin-crons, der kan sende mail: outbox_send (5 min), send_reminders, meeting_pending_reminder og pending_kollega_reminder. De går til deltagere, ikke johan@.
- **cbcit.dk:** admin_email johan@, ca. 30 plugins på autoupdate (WP sender en mail efter hver autoupdate-kørsel). Wordfence `alertEmails=johan@`, alarmer ved adminLogin (kun første), breachLogin, critical, loginLockout, **lostPasswdForm**, scanIssues, warnings og deaktivering, samt ugentligt `email_summary`, og `notification_promotions/blogHighlights/productUpdates=1` (dashboard). WooCommerce: new_order og cancelled_order går til **info@**, ikke johan@. Really Simple SSL har sårbarheds-notifikation.
- **datagaarden.dk:** admin_email johan@, 13 plugins på autoupdate, `WP_AUTO_UPDATE_CORE` er ikke defineret (minor-default). Wordfence er aktiv, men dens mail-options blev ikke hentet (scriptet læste kun Wordfence-options på cbcit.dk). **Site Kit email-reporting**-crons er aktive (`googlesitekit_email_reporting_*`). Complianz har ugentlige og månedlige hooks.

**10. Egne logs, 14 dage.** advisory-watch har sendt mail **hver dag** 1.–6/11 (3→4→5 afvigelser) + ugemail 2/11. security-updates har sendt tre mails (4/11: 8 pakker, 5/11: 11, 6/11: 1). wp-integrity, backup-check og egress-report skriver ikke "mail sendt" i deres logs, og `cbc-egress-report.log` findes ikke. Advisory-rapporten 6/11: WP 7.1.4 mangler på event (DISALLOW_FILE_MODS), cbcit.dk mangler webappick 8.0.42 + turnstile 1.44.5 (begge med sikkerheds-flag), datagaarden mangler wp-fastest-cache 1.5.5 + complianz 7.5.7, Plesk 18.0.82 findes, apt mangler ca-certificates. PHP 8.4.27 = upstream, egress-filteret står på enforce.

**11. Hardening-README.** Mail er nævnt for egress-rapport (06:55), fail-safe-mail fra ranges-fetch, security-updates (kun ved ændring), advisory-watch (check/weekly, state i `reported-plugins.txt`), og dead-man-afsnittet (2026-11-04).

## Afvigelser fra 04-drift.md §2–4

### Live ≠ docs
1. **Imunify-scan kører månedligt, ikke dagligt.** Ifølge 04 §4 sker scanningen "dagligt 03:00" (07 §-tjeklisten siger det samme), men live-config er `interval: month, day_of_month: 28, hour: 3`. Enten er den daglige scanning aldrig blevet sat, eller også er den blevet nulstillet (fx af en Imunify-opdatering). Det skal rettes eller dokumenteres.
2. **`cbc-update-notify.php` kører 07:30 CET, ikke "07:30 UTC".** Crontab-kommentaren og 04 §2.3 skriver UTC, men cron kører i serverens lokale tid, så den kører 07:30 CET, samme minut som advisory-weekly.
3. **Backup-filen `cbc-egress-report.pre-hc-20261104` ligger i `/etc/cron.d`.** Den er ikke nævnt i docs. Den er formentlig inaktiv (punktum i filnavnet), men bør flyttes til `/root/cbc-hardening-2026-10/backup/`.
4. **`cbc-woo-order-watch` har ingen output-omdirigering i cron**, og det gælder også `cbc-hc-ping.sh` i egress-linjen. Hvis de skriver noget til stdout/stderr, sender cron en mail til root. Root har intet alias, og `server.cbcit.dk` står ikke i `mydestination`, så sådan en mail bliver relayet til Brevo mod en adresse uden MX og går tabt eller bouncer stille. Det er ikke dokumenteret.
5. **Mail-afsendere:** wp-integrity sender som `noreply@cbcit.dk`, fire scripts sender uden From (→ root@server.cbcit.dk). 04 §3 nævner kun `cbc_noreply_email` og `cbc_contact_email` (plugin). Det har betydning for DMARC-skridtet til `p=quarantine` (04 §3.2 kræver "header-test af server-cron-mails" først).
6. **Postfix-loggen** hedder `/var/log/maillog` (+ `.processed`). 04 §4 nævner ingen mail-log overhovedet.
7. **advisory-watch "kun første gang".** README beskriver, at den daglige mail kun sendes første gang en opdatering ses eller ved sikkerheds-flag. Live sendes der mail hver dag, fordi to af de afventende cbcit.dk-plugins har sikkerheds-flag. Det er teknisk som designet, men i praksis bliver det til daglig støj, indtil de opdateres.

### Docs mangler (live mail-kilder til johan@, ikke i 04 §2.3/§4)
8. **WordPress core-mails fra alle tre sites** (admin_email = johan@): autoupdate-resultater for ca. 30 plugins (cbcit.dk) og 13 plugins (datagaarden), minor-core-updates og recovery-mode-mails.
9. **Wordfence** på cbcit.dk (alarmer + ugentligt resumé, bl.a. *lostPasswdForm* = mail hver gang nogen bruger "glemt password") og på datagaarden (config ikke hentet).
10. **Site Kit email-reporting** (datagaarden) og **Really Simple SSL**-sårbarhedsmails. Modtager er ikke verificeret.
11. **Plesk `autoupdates-email-notification`** = johan@ (komponent-autoupdates) og Plesk-extension-notifier (TLS- og mail-port-tjek).
12. 04 §2.3-tabellen nævner ikke, at **fail2ban `destemail`** er sat uden mail-action. Det er harmløst, men værd at notere, så ingen tror, der kommer ban-mails.

### Docs → live: bekræftet
Relay via Brevo, TLS encrypt og loopback-only stemmer. CBC-cron-planer og healthchecks-ping på egress stemmer. backup-check 06:40 sender ingen mail. Imunify ADMIN_CONTACTS og Plesk-backup-mail = johan@ stemmer. Auto-reboot 04:00 stemmer (01 §2 / 03). Alle tre sites har system-cron `*/5` med 512M. WooCommerce-ordremails går til info@ (ikke johan@).

### Ikke verificerbart i denne kørsel
`smtp_sasl_auth_enable` (filtreret). `cbc_purge_expired_magic_tokens` og `cbc_event_log_purge` er ikke med i grep-filteret over cron-listen og blev derfor ikke vist, så det er ikke et fund. Plesks dmarc-rapport-modtager kendes ikke. Wordfence-mail-options på datagaarden er ikke hentet.

## Faktiske mails til johan@ seneste 14 dage: afsender → antal

Postfix-loggen, 23/10–6/11-2026. Alle 128 leveringer har `status=sent` (0 bounces/deferred), i snit ca. 9 om dagen (spænd 4–16). Envelope-afsenderen er omskrevet af `sender_canonical` (`/@(event|server)\.cbcit\.dk$/ → noreply@cbcit.dk`), så tabellen viser også den oprindelige afsender fra pickup-linjen.

| Envelope-afsender | Oprindelig afsender (uid) | Antal | Hvad det er |
|---|---|---:|---|
| `noreply@cbcit.dk` | `root` (uid 0), msgid @server.cbcit.dk | **55** | CBC-root-scripts: egress-rapport (~14), advisory-watch (6), security-updates (3), wp-integrity, fw-refresh, woo-watch m.fl. De kan ikke skilles ad uden subject-logning. |
| `salg@datagaarden.dk` | `datagaardendk` (uid 10002) | **31** | datagaarden.dk-WordPress: 20 med msgid @www.datagaarden.dk (sandsynligvis Contact Form 7-henvendelser) + 11 @server.cbcit.dk (WP-core/plugin-mails, fx autoupdate/Wordfence) |
| `wordpress@cbcit.dk` | `cbcitdk` (uid 10001) | **18** | cbcit.dk WP-core-mails (autoupdate-rapporter, Wordfence m.fl.) |
| `johan@cbcit.dk` | uid 999 (ikke mappet, formentlig Plesk-proces) | **11** | Plesk-notifikationer: backup-rapport, autoupdates m.fl. |
| `info@cbcit.dk` | `cbcitdk` (uid 10001), msgid @www.cbcit.dk | **7** | cbcit.dk med info@ som afsender: WooCommerce- eller CF7-mails, hvor johan@ er modtager |
| `noreply@cbcit.dk` | `root@server.cbcit.dk` (uid 999) | **3** | Plesk-proces sender som root (fx Imunify/Plesk-alarmer) |
| `noreply@cbcit.dk` | event-sysuser (uid 10000) | **3** | event.cbcit.dk: `cbc-update-notify.php` (mandag) + 1 WP-mail |
| | | **128** | |

**Pr. dag:** 23/10 10 · 24/10 7 · 25/10 4 · 26/10 15 · 27/10 9 · 28/10 16 · 29/10 9 · 30/10 8 · 31/10 5 · 1/11 7 · 2/11 10 · 3/11 8 · 4/11 6 · 5/11 8 · 6/11 6 (indtil 11:35).

**Konsekvens for digest:** Ca. 43 % kommer fra CBC-root-scripts, som vi selv styrer og kan samle direkte. Ca. 50 % kommer fra de tre WordPress-sites og Plesk, og de kan kun samles ved at ændre modtager/notifikationer i WP/Wordfence/Plesk eller ved at filtrere i indbakken. Datagaardens 31 mails er den største enkeltkilde uden for CBC-scripts. Det skal afklares, om det er kundehenvendelser (skal ikke i en digest) eller notifikationer.
