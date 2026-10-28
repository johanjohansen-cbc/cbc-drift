# CBC Driftsdokumentation — 03 · Software & sites

> Software-stack + versioner + opdateringspolitik · opsætning pr. site.
> **Verificeret:** 2026-07-20 via live SSH (`plesk version`, `php -v`, `wp core
> version`, `plesk bin subscription`, `wp plugin list`); **re-verificeret
> 2026-10-26** (fuld audit, alle versioner nedenfor er fra den dato).

---

## 1. Software-stack

| Komponent | Version (2026-10-26) | Noter |
|---|---|---|
| **OS** | Ubuntu 24.04.5 LTS (kernel 6.8.0-147) | `unattended-upgrades` + `cbc-security-updates.sh` hver 4. time |
| **Panel** | Plesk Obsidian 18.0.81.4 | Auto-patcher egne komponenter natligt ~06:25 |
| **Web (reverse proxy)** | nginx 1.30.5 | Foran Apache; serverer statiske assets + proxy |
| **Web (backend)** | Apache 2.4.58 | PHP via FPM; `mod_remoteip`, ModSecurity |
| **PHP** | 8.3.36 + **8.4.27** installeret; **kun `plesk-php84-fpm` aktiv** | Alle tre sites på 8.4-poolen. 8.4.27 = fix for CVE-2026-109618/109619 (installeret 22/10 06:32) |
| **Database** | MariaDB 10.11.14 | Kun `127.0.0.1:3306`; én DB-bruger pr. site med rettigheder kun til egen DB |
| **WP-CLI** | `/usr/local/bin/wp` (Plesk WP Toolkit-wrapper) | Køres altid som sysuser via `su`, med `-d memory_limit=512M`; på cbcit.dk desuden `--skip-themes` — se 04-drift |
| **git** | 2.43.0 | Deploy via bare repos |
| **composer** | `/usr/local/bin/composer` = **bash-wrapper, ikke phar** | `composer install` er hverken nødvendig eller mulig på boksen; `vendor/` er committet i repoet |
| **cloudflared** | 2026.10.4 (systemd-service, aktiv) | Cloudflare Tunnel — se 02-adgang §4. Opdateres af `cbc-security-updates.sh` |
| **Imunify** | ImunifyAV 8.10.1 | Daglig malwarescan 03:00 — se 02 §5 |

---

## 2. Opdateringspolitik (frysen ophævet 2026-10-08)

Versions-frysen før september-konferencen er **ophævet**. Gældende politik:

| Lag | Mekanik | Hvem/hvornår |
|---|---|---|
| **OS-security + Plesk-PHP + cloudflared/Imunify** | Automatisk: `cbc-security-updates.sh` hver 4. time + `unattended-upgrades` + auto-reboot 04:00 ved kerne-opdatering | Ingen manuel handling; mail ved ændring/fejl |
| **Plesk-komponenter** (panel, nginx, MariaDB …) | Automatisk: Plesks natkørsel ~06:25 | — |
| **WordPress core – minor/security** | `WP_AUTO_UPDATE_CORE='minor'` (event) / default (cbcit, datagaarden) → WP patcher selv inden for samme major | Overvåges af advisory-watch + integritetstjek |
| **WordPress core – MAJOR** (fx 7.1 → 7.2) | **Manuelt, kun mellem konferencer**, altid: Hetzner-snapshot + DB-dump først, test på Local først, `wp core update` som sysuser, smoke-test. 2026-10-08: 7.0.4 → 7.1.3 på alle tre (gotcha: ingen da_DK-pakke → `--locale=en_US` + `wp site switch-language da_DK`; `verify-checksums --locale=en_US`) | Johan + Claude |
| **Plugins/temaer event.cbcit.dk** | `DISALLOW_FILE_MODS=true` → kun via git-deploy (CBC-plugin/tema) eller manuel `wp plugin update` (duplicate-post). Ugentlig notify-mail mandag 07:30 hvis noget venter | Deploy-runbook 04 §1 |
| **Plugins/temaer cbcit.dk + datagaarden.dk** | **Auto-update slået til på de fleste plugins** (WP's egen mekanik); premium-plugins (Flatsome, FCF Pro, WebAppick) opdateres manuelt | Advisory-watch mailer ved ventende opdateringer med sikkerheds-ord i changelog |
| **PHP major** (8.5.x) | Kun efter test på Local; aldrig automatisk (Plesk-repoet er pinned til `PHP84_17`) | Johan |

> **Patch-vindue for 0-days:** PHP/OS ≤ 4 t (cron). WP-core minor: WP's egen
> auto-update (typisk < 24 t). Plugins med sikkerhedsfix på cbcit/datagaarden:
> WP auto-update (typisk < 24 t). Varsling uafhængigt af partnere: advisory-watch
> (07:15) + Plesk/WP-feeds. Dette blev indført efter PHP-RCE'en 21/10-2026, hvor
> CBC kun blev varslet af en partner.

---

## 3. Sites på boksen

Tre Plesk-subscriptions, alle på IP `178.104.70.94`, alle `<sysuser>:psaserv`-ejet.

### 3.1 `event.cbcit.dk` — CBC Event Planner (primær)

| | |
|---|---|
| **Formål** | Konference-/deltagerportal (kickoff september 2026) |
| **Sysuser** | `event.cbcit.dk_x3pjx5okzbn` (gruppe `psaserv`; temaer dog `psacln`) |
| **Docroot** | `/var/www/vhosts/event.cbcit.dk/httpdocs` |
| **WordPress** | **7.1.3** (major 2026-10-08; en_US-pakke + `WPLANG=da_DK`) |
| **Plugins (aktive)** | `cbc-event-planner` **2.7.0** · `duplicate-post` 4.7 · `two-factor` 0.17.0 (2FA, siden 2026-10-28) · mu-plugins `cbc-no-user-enum` + `cbc-admin-2fa` (02 §7.2d) |
| **Tema** | `cbc-child` 0.6.7 (child af `twentytwentyfive` 1.5) |
| **DB-prefix** | Custom (ikke `wp_`) |
| **Brugere** | 182 (3 administratorer med 2FA-krav: `cbcadmin` [johan@cbcit.dk], `anja@cbcit.dk`, `jan@cbcit.dk` — alle tre også `cbc_participant`; ~100 `cbc_participant`, ~80 `cbc_vendor`). `janadmin` slettet 2026-10-28. `blog_public=0`, `users_can_register=0`. Admins logger ind via `wp-login.php` + TOTP; magic-link virker ikke for dem. |
| **Fronting** | Cloudflare (proxy + WAF; Managed Challenge på `wp-login.php`; XML-RPC lukket) |
| **Kode** | Deploy via bare repos `/var/git/cbc-event-planner.git` + `/var/git/cbc-child.git` (se 04-drift) |

> `duplicate-post` bruges til at klone indhold i admin. Det er *ikke* nævnt i de
> gamle plugin-docs, men er en aktiv, legitim afhængighed. Plugin-versionshistorik
> (1.x → 2.7.0, multikonference-arkitektur efter konferencen) står i plugin-repoets
> `docs/` og CHANGELOG — ikke her.

### 3.2 `cbcit.dk` — WordPress + WooCommerce (webshop)

| | |
|---|---|
| **Formål** | CBC's hoveddomæne — fuldt WordPress-site **med WooCommerce-webshop og live betalingsgateway (QuickPay)**. Docroot indeholder desuden løse marketing-HTML-filer (`cbc-spot.html` m.fl.) + domæne-verifikationsfiler. |
| **Sysuser** | `cbcitdk` (gruppe `psaserv`) |
| **Docroot** | `/var/www/vhosts/cbcit.dk/httpdocs` |
| **WordPress** | **7.1.3** |
| **Webshop** | `woocommerce` 11.2.1 · `woocommerce-quickpay` 8.0.3 (**betalinger!** — eneste aktive gateway; `3d-creditcard` + 10-min betalingslink siden 21/10) · `flexible-checkout-fields` 4.1.44 (+pro 4.0.32) · `webappick-product-feed` 8.0.40 · `wp-store-locator` · `woosidebars` · `simple-cloudflare-turnstile` 1.44.0 · mu-plugin `cbc-checkout-guard` (02 §7.2d) |
| **Øvrige plugins (aktive)** | `wordfence` 9.0.2, `wordpress-seo` (Yoast) 28.7, `akismet`, `contact-form-7`, `mailchimp-for-wp`, `really-simple-ssl`, `wps-hide-login`, `tablepress`, `shortcoder`, `getsitecontrol`, `widget-options`, `regenerate-thumbnails`, `media-cleaner`, `duplicate-post`, `cbc-tilbudsavis-fields` (eget), **`all-in-one-wp-migration`** 7.112 (⚠️ audit-fund 2026-10-26: aktivt, kan eksportere hele site+DB fra admin og har vuln-historik — deaktivér når det ikke bruges) |
| **Tema** | `cbc-child` **3.0** (child af **Flatsome** 3.20.11, premium) — ⚠️ navnesammenfald: alle tre sites har hver deres *forskellige* tema ved navn `cbc-child` (event=0.6.7/TT5, cbcit=3.0/Flatsome, datagaarden=3.0/Flatsome). De er IKKE samme kodebase. |
| **Brugere** | 17 (2 administratorer: `johan` + `Kent` [kgrady@kobalt.dk, ekstern]; 1 shop_manager; 14 kunder). Ingen 2FA (åbent). |
| **Fronting** | Cloudflare + origin-guard (403 uden om CF) + CF Managed Challenge på checkout + XML-RPC lukket |
| **Cron** | ✅ **Lukket okt. 2026:** `DISABLE_WP_CRON=true` + system-cron for `cbcitdk` hvert 5. min (`wp cron event run --due-now`, 512M). WooCommerce Action Scheduler kører nu uafhængigt af besøgstrafik. |
| **WP-CLI-gotcha** | `wp` mod dette site **OOM'er på default 128M** (Flatsome + FCF Pro) → kør altid `/opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp … --skip-themes` som `cbcitdk` (Plesk-wrapperen ignorerer `WP_CLI_PHP_ARGS`). Options ændres sikrest via `wp eval-file` (scp'et fil) — heredocs i ssh-kommandoer knækker på quoting. |
| **Historik** | Card-testing-angreb 18–21/10-2026 (272 svindelordrer via `POST /?wc-ajax=checkout`, BIN 448975, varslet af Clearhaus). Rodårsager: manglende real-IP bag CF, ingen bot-værn på checkout, intet svindel-filter i gateway — alle lukket 21/10 (02 §7.2e). Nul angrebsordrer siden. |

### 3.3 `datagaarden.dk` — selvstændigt WordPress-site (CF-for-SaaS)

| | |
|---|---|
| **Formål** | Selvstændigt business-/marketing-site (ikke CBC-konferencen). Migreret ind 2026-07-10→17. |
| **Sysuser** | `datagaardendk` (gruppe `psaserv`; **ingen shell** — `/bin/false`) |
| **Docroot** | `/var/www/vhosts/datagaarden.dk/httpdocs` (3,84 GB) |
| **WordPress** | **7.1.3** |
| **Plugins (aktive, 13)** | `wordfence` 9.0.2, `complianz-gdpr`, `contact-form-7`, `really-simple-ssl`, `wps-hide-login`, `google-site-kit`, `official-facebook-pixel`, `wp-fastest-cache` (erstattede `wp-cloudflare-page-cache`), `wp-consent-api`, `insert-headers-and-footers` (WPCode — kan køre PHP-snippets som admin!), `classic-editor`, `duplicate-page`, `media-cleaner`. Alle med auto-update. |
| **Tema** | `cbc-child` 3.0 (child af **Flatsome** 3.20.11) — separat kodebase, ikke koblet til CBC-deploy. |
| **Brugere** | 7 — **alle administratorer** (Datagaardens ansatte + `johan`). Audit-fund 2026-10-26: ingen 2FA, og alle har admin selv om de kun redigerer indhold → nedgradér til `editor` + 2FA (udsat af Johan). |
| **Fronting** | **Cloudflare for SaaS** (siden 2026-08-26): custom hostnames i cbcit.dk-zonen, DNS hos **wwi**, www-CNAME + apex-ANAME → `sites.cbcit.dk`. IDN-alias `datagården.dk` (`xn--datagrden-92a.dk`) redirecter til apex. Se 01 §4.1 + 02 §7.2b. Origin-cert = Plesk-selvsigneret (01 §4.3, åbent). |
| **Sikkerhed** | Wordfence (app-WAF) + `wps-hide-login` + origin-guard og CF-real-ip (siden 2026-08-27) + request-grænser + XML-RPC lukket (okt. 2026). `?author=N` giver 500 (plugin-kollision, skjuler i praksis brugernavne — ikke undersøgt). |
| **Cron** | `DISABLE_WP_CRON=true` + system-cron for `datagaardendk` hvert 5. min. |
| **SFTP** | Datagaardens folk uploader filer direkte i docroot via SFTP-chroot (02 §2.1) — bl.a. `/Support/` med `TeamViewerQS.exe` (31 MB), PDF og HTML. ⚠️ Audit-fund: en offentligt hostet .exe kan ved site-kompromittering byttes til malware mod Datagaardens kunder — link til TeamViewer i stedet (åbent, Datagaarden). |
| **Status** | **LIVE bag CF** siden 2026-08-26; Kents-LB-broen (juli-august, `KENTS-LB-TEMP`) er nedlagt og firewall/fail2ban ryddet op 2026-08-27. |

---

## 4. Plesk-extensions (installeret)

`imunify360` (malware) · `one-drive-backup` · `letsencrypt` · `sectigo`/`symantec`
(SSL) · `sslit` · `mfa` · `monitoring` · `git` · `wp-toolkit` · `nodejs` ·
`laravel` · `log-browser` · `repair-kit` · `site-import` · `ntp-timesync` ·
`advisor` · `sitejet` · `xovi` (SEO) · `configurations-troubleshooter` ·
`ssh-terminal` · `composer`.

> Audit-note 2026-10-26: **WP Toolkit har ingen registrerede WP-instanser**
> (`plesk ext wp-toolkit --list` er tom) — dens auto-update-/scan-crons er
> derfor no-ops; WP-vedligehold sker via wp-cli/advisory-watch. Flere extensions
> bruges ikke (`sitejet`, `nodejs`, `laravel`, `composer`, `xovi`, `site-import`,
> `ssh-terminal` = web-shell som root i panelet). Lav risiko fordi panelet kun
> nås via Access/tunnel, men oprydning er en nem reduktion af angrebsflade.

---

## 5. Verifikations-kommandoer

```bash
ssh cbc-prod 'plesk version; /opt/plesk/php/8.4/bin/php -v | head -1; mariadb --version; cloudflared --version; imunify360-agent version'
# WP-version + ventende opdateringer pr. site (sysuser, 512M, --skip-themes pga. Flatsome/FCF Pro):
for d in event.cbcit.dk:event.cbcit.dk_x3pjx5okzbn cbcit.dk:cbcitdk datagaarden.dk:datagaardendk; do
  ssh cbc-prod "su -s /bin/bash ${d##*:} -c '/opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp --path=/var/www/vhosts/${d%%:*}/httpdocs --skip-themes core version; /opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp --path=/var/www/vhosts/${d%%:*}/httpdocs --skip-themes plugin list --update=available --fields=name,version,update_version'"
done
ssh cbc-prod '/usr/local/sbin/cbc-advisory-watch.sh show'   # samlet rapport: PHP/WP/plugins/Plesk mod upstream
```
