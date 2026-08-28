# CBC Driftsdokumentation — 03 · Software & sites

> Software-stack + versioner + frys-politik · opsætning pr. site.
> **Verificeret:** 2026-07-20 via live SSH (`plesk version`, `php -v`, `wp core
> version`, `plesk bin subscription`, `wp plugin list`).

---

## 1. Software-stack

| Komponent | Version | Noter |
|---|---|---|
| **OS** | Ubuntu 24.04.4 LTS (kernel 6.8.0-136) | `unattended-upgrades` aktiv |
| **Panel** | Plesk Obsidian 18.0.78.4 | Auto-patcher OS/PHP/DB/nginx |
| **Web (reverse proxy)** | nginx 1.30.2 | Foran Apache; serverer statiske assets + proxy |
| **Web (backend)** | Apache 2.4.58 | PHP via FPM |
| **PHP** | 8.3 + **8.4.23** installeret; **kun `plesk-php84-fpm` aktiv** | App kører 8.4 |
| **Database** | MariaDB 10.11.14 | Kun `127.0.0.1:3306` |
| **WP-CLI** | Installeret (`/usr/local/bin/wp`) | Køres altid som sysuser via `su` — se 04-drift |
| **git** | 2.43.0 | Deploy via bare repos |
| **composer** | `/usr/local/bin/composer` = **bash-wrapper, ikke phar** | `composer install` er hverken nødvendig eller mulig på boksen; `vendor/` er committet i repoet |
| **cloudflared** | Systemd-service (aktiv) | Cloudflare Tunnel — se 02-adgang §4 |

---

## 2. Versions-frys-politik (KRITISK)

**Frem til efter konferencen (september 2026) fryses app-laget:**

- **WordPress-core 7.0.1** — ingen major/minor-opgradering før efter eventet.
- **PHP 8.4** — ingen skift til 8.5.x.
- **Plugin/tema (CBC)** — deployes kontrolleret via git; ingen ad-hoc-ændringer.

**Mekanik der håndhæver frysen:**
- `DISALLOW_FILE_MODS=true` i wp-config → WP kan ikke selv installere/opdatere.
- `WP_AUTO_UPDATE_CORE='minor'` → kun sikkerheds-/minor-auto-patch tillades.
- **Ugentlig notify-cron** (mandag 07:30) mailer admin hvis opdateringer venter —
  men **installerer intet** (se 04-drift §cron). Opdateringer anvendes manuelt
  efter backup + smoke-test.

> Efter konferencen: planlæg core/PHP-opgradering i et vedligeholdelsesvindue med
> forudgående restore-punkt (se 05-backup).

---

## 3. Sites på boksen

Tre Plesk-subscriptions, alle på IP `178.104.70.94`, alle `<sysuser>:psaserv`-ejet.

### 3.1 `event.cbcit.dk` — CBC Event Planner (primær)

| | |
|---|---|
| **Formål** | Konference-/deltagerportal (kickoff september 2026) |
| **Sysuser** | `event.cbcit.dk_x3pjx5okzbn` (gruppe `psaserv`; temaer dog `psacln`) |
| **Docroot** | `/var/www/vhosts/event.cbcit.dk/httpdocs` |
| **WordPress** | 7.0.1 |
| **Plugins (aktive)** | `cbc-event-planner` **1.29.1** · `duplicate-post` 4.6 |
| **Tema** | `cbc-child` 0.6.5 (child af `twentytwentyfive`) |
| **DB-prefix** | Custom (ikke `wp_`) |
| **Fronting** | Cloudflare (proxy + WAF + Access på admin-vej) |
| **Kode** | Deploy via bare repos `/var/git/cbc-event-planner.git` + `/var/git/cbc-child.git` (se 04-drift) |

> `duplicate-post` bruges til at klone indhold i admin. Det er *ikke* nævnt i de
> gamle plugin-docs, men er en aktiv, legitim afhængighed.

### 3.2 `cbcit.dk` — WordPress + WooCommerce (webshop)

| | |
|---|---|
| **Formål** | CBC's hoveddomæne — fuldt WordPress-site **med WooCommerce-webshop og live betalingsgateway (QuickPay)**. Docroot indeholder desuden løse marketing-HTML-filer (`cbc-spot.html` m.fl.) + domæne-verifikationsfiler. |
| **Sysuser** | `cbcitdk` (gruppe `psaserv`) |
| **Docroot** | `/var/www/vhosts/cbcit.dk/httpdocs` |
| **WordPress** | **7.0** — bemærk: én patch-release BAG de to andre sites (7.0.1). |
| **Webshop** | `woocommerce` 10.9.1 · `woocommerce-quickpay` 8.0.3 (**betalinger!**) · `flexible-checkout-fields`(+pro) · `webappick-product-feed` · `wp-store-locator` · `woosidebars` |
| **Øvrige plugins (aktive)** | `wordfence` 8.2.2, `wordpress-seo` (Yoast) 27.9, `akismet`, `contact-form-7`, `mailchimp-for-wp`, `really-simple-ssl`, `wps-hide-login`, `tablepress`, `shortcoder`, `getsitecontrol`, `widget-options`, `regenerate-thumbnails`, `media-cleaner`, `duplicate-post`, **`all-in-one-wp-migration`** (kan lægge store eksporter m. fuld DB i webroot — brug med omtanke) |
| **Tema** | `cbc-child` **3.0** — ⚠️ navnesammenfald: alle tre sites har hver deres *forskellige* tema ved navn `cbc-child` (event=0.6.5, datagaarden=eget, cbcit=3.0). De er IKKE samme kodebase. |
| **Fronting** | Cloudflare + origin-guard (403 uden om CF) |
| **Cron** | ⚠️ **Ingen `DISABLE_WP_CRON`, ingen system-cron for `cbcitdk`** → request-drevet wp-cron. WooCommerce's schedulerede jobs (Action Scheduler) kører kun ved besøgstrafik. Overvej samme system-cron-mønster som event (se 04-drift §2.1). |
| **WP-CLI-gotcha** | `wp` mod dette site **OOM'er på default 128M** (WooCommerce-load) → brug altid `-d memory_limit=512M`. |

### 3.3 `datagaarden.dk` — selvstændigt WordPress-site (CF-for-SaaS)

| | |
|---|---|
| **Formål** | Selvstændigt business-/marketing-site (ikke CBC-konferencen). Migreret ind 2026-07-10→17. |
| **Sysuser** | `datagaardendk` (gruppe `psaserv`; **ingen shell** — `/bin/false`) |
| **Docroot** | `/var/www/vhosts/datagaarden.dk/httpdocs` (3,84 GB) |
| **WordPress** | 7.0.1 |
| **Plugins (aktive)** | `wordfence`, `complianz-gdpr`, `contact-form-7`, `really-simple-ssl`, `wps-hide-login`, `google-site-kit`, `official-facebook-pixel`, `wp-cloudflare-page-cache`, `wp-consent-api`, `insert-headers-and-footers`, `classic-editor`, `duplicate-page`, `media-cleaner` |
| **Tema** | `cbc-child` — **NB:** navnesammenfald med event's tema; verificér at det er et *separat* tema, ikke det samme repo (datagaardens er ikke koblet til CBC-deploy). |
| **Fronting** | **Cloudflare for SaaS** (siden 2026-08-26): custom hostnames i cbcit.dk-zonen, DNS hos **wwi**, www-CNAME + apex-ANAME → `sites.cbcit.dk`. IDN-alias `datagården.dk` (`xn--datagrden-92a.dk`) redirecter til apex. Se 01 §4.1 + 02 §7.2b. |
| **Sikkerhed** | Wordfence (app-WAF) + `wps-hide-login` + origin-guard og CF-real-ip (siden 2026-08-27). |
| **Status** | **LIVE bag CF** siden 2026-08-26; Kents-LB-broen (juli-august, `KENTS-LB-TEMP`) er nedlagt og firewall/fail2ban ryddet op 2026-08-27. |

> `wp-cloudflare-page-cache` er aktivt på datagaarden — pegede historisk på sitets
> GAMLE CF-setup (ex-partnerens konto). Efter flippet til CBC's zone bør det
> verificeres/omkonfigureres (API-token/zone i plugin'et er næppe vores).

---

## 4. Plesk-extensions (installeret)

`imunify360` (malware) · `one-drive-backup` · `letsencrypt` · `sectigo`/`symantec`
(SSL) · `sslit` · `mfa` · `monitoring` · `git` · `wp-toolkit` · `nodejs` ·
`laravel` · `log-browser` · `repair-kit` · `site-import` · `ntp-timesync` ·
`advisor` · `sitejet` · `xovi` (SEO) · `configurations-troubleshooter` ·
`ssh-terminal` · `composer`.

---

## 5. Verifikations-kommandoer

```bash
ssh cbc-prod 'plesk version; /opt/plesk/php/8.4/bin/php -v | head -1; mariadb --version'
for d in event.cbcit.dk datagaarden.dk; do
  ssh cbc-prod "su -s /bin/bash \$(stat -c '%U' /var/www/vhosts/$d/httpdocs) -c \
    '/opt/plesk/php/8.4/bin/php /usr/local/bin/wp --path=/var/www/vhosts/$d/httpdocs core version'"
done
```
