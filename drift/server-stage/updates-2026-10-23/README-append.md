

---

# Sikkerhedsopdateringer hver 4. time + advisory-overvågning — 2026-10-23

Baggrund: PHP-RCE'en CVE-2026-109618/109619 (21/10) blev først patchet af Plesks natkørsel 22/10 kl. 06:32 (~14 t efter
release), og CBC blev kun varslet af en partner. Mål: patch-vindue ≤ 4 t for PHP + Ubuntu-security, og Johan skal selv kunne
se hvor serveren står (mail ved afvigelse + ugentlig "alt OK").

## Hvad Plesk selv gør (verificeret i /var/log/plesk/install/autoinstaller3.log + ai_action_time.xml)
- `/etc/cron.daily/50plesk-daily` → `sw-engine-pleskrun .../DailyMaintainance/script.php` → kl. ~06:25 kører
  `/opt/psa/admin/bin/autoinstaller --select-product-id plesk --show-releases --enable-xml-output --branch release,stable`,
  `... --select-release-current --show-upgradable-components --enable-xml-output` og, hvis noget er nyt,
  **`/opt/psa/admin/bin/autoinstaller --select-product-id plesk --select-release-current --upgrade-installed-components`**
  (22/10 06:29–06:32: Plesk 18.0.81.4 + plesk-php84 8.4.26→8.4.27 + plesk-php83 8.3.35→8.3.36 + nginx m.fl.).
- Plesks PHP-repoer står **permanent** i `/etc/apt/sources.list.d/plesk.list` (`PHP84_17`, `PHP83_17`, pool-"extras") →
  almindelig `apt-get` kan opgradere `plesk-php8*` uden autoinstaller. `plesk-php84-fpm`'s postinst kører
  `systemctl condrestart plesk-php84-fpm.service` (FPM genstartet 22/10 06:32:07 = configure-tidspunktet i dpkg.log), og
  `plesk-php84-cli`'s postinst kører `packagemng -sdf` (Plesk-registret). Lås: `/var/lock/psa-installer.lock` + proces `autoinstaller`.
- Ubuntu: `unattended-upgrades` aktiv (apt-daily ~01:20, apt-daily-upgrade ~02:10), Allowed-Origins = noble, noble-security, ESM.

## 1. `/usr/local/sbin/cbc-security-updates.sh` — cron `/etc/cron.d/cbc-security-updates` (00:45, 04:45, 08:45, 12:45, 16:45, 20:45)
1. `flock -n /run/lock/cbc-security-updates.lock`; **springer over** (kun log) hvis autoinstaller-proces kører, `psa-installer.lock`
   er holdt, eller apt/dpkg-låsen er taget.
2. dpkg-snapshot før → `apt-get update -qq` → `apt-get -s install --only-upgrade <alle installerede plesk-php8*>` → kun hvis
   `Inst plesk-php8…`-linjer: `apt-get -y -o Dpkg::Options::=--force-confdef -o …=--force-confold install --only-upgrade <dem>`.
   Ved plesk-php84-*: sammenligner FPM `ActiveEnterTimestampMonotonic` før/efter — genstarter selv hvis pakken ikke gjorde det;
   `plesk bin php_handler --reread`.
3. `unattended-upgrade -v` (Ubuntu-security, samme regler som natkørslen) → dpkg-snapshot efter → diff = faktiske ændringer.
4. **Mail til johan@cbcit.dk KUN hvis ≥1 pakke ændret (eller fejl)**: pakke gammel→ny, PHP-version før/efter, om FPM blev
   genstartet (af pakken eller scriptet), FPM-status, HTTP-kode for de tre sites, reboot-required.
   Afsender `cbc-security-updates@server.cbcit.dk`. Log: `/var/log/cbc-security-updates.log` (logrotate ugentlig ×12).
- Manuelt: `cbc-security-updates.sh --dry-run` (viser plan, ændrer intet) · `--test-mail` · normal kørsel uden argumenter.
- Rollback/slå fra: `rm /etc/cron.d/cbc-security-updates` (Plesks natkørsel + apt-daily fortsætter uændret).
- Bevidst: plesk-php83 (installeret, inaktiv) opgraderes også; andre Plesk-komponenter (nginx, psa, imunify) overlades til Plesks natkørsel;
  ikke-security Ubuntu-pakker (noble-updates: cloud-init, tmux, ubuntu-pro-client …) opgraderes IKKE automatisk (vises i ugemailen).

## 2. `/usr/local/sbin/cbc-advisory-watch.sh` — cron `/etc/cron.d/cbc-advisory-watch`
- `check` dagligt 07:15 (ikke mandag) → mail KUN ved afvigelse. `weekly` mandag 07:30 → status-mail ALTID ("alt OK" eller
  "N afvigelser"). `show` = fuld rapport på stdout, ingen mail/state. Afsender `cbc-advisory-watch@server.cbcit.dk`.
- Kilder (bash + curl + Plesks PHP-CLI til JSON; jq findes ikke, ingen nye runtimes):
  1. PHP: `https://www.php.net/releases/index.php?json&version=8.4` (`version`, `date`, `tags`) vs `/opt/plesk/php/8.4/bin/php -r 'echo PHP_VERSION;'`
     + Plesk-repoets kandidat (`apt-cache policy plesk-php84`) → teksten siger om man kan hente nu eller skal vente på Plesk.
  2. WordPress: `https://api.wordpress.org/core/version-check/1.7/` (`offers[0].version`) vs `wp core version` pr. site
     (wp-cli som sysuser: `su -s /bin/bash <sysuser> -c "cd <docroot> && /opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp … --skip-themes"`).
  3. Plugins: `wp plugin list --update=available` pr. site; hver opdatering slås op i `api.wordpress.org/plugins/info/1.2`, og den
     nyeste changelog scannes for sikkerheds-ord (security/vulnerab/XSS/CSRF/SQLi/CVE…) → `[SIKKERHED? …]` / `[changelog uden
     sikkerheds-ord]` / `[ikke paa wp.org (premium)]`. Daglig mail kun første gang en opdatering ses eller ved sikkerheds-flag
     (state `/var/lib/cbc-advisory/reported-plugins.txt`); ugemailen lister alle afventende.
     **Begrænsning:** Wordfence' gratis sårbarhedsfeed er lukket (HTTP 410/401 pr. 23/10-2026), WPScan/Patchstack kræver API-nøgle →
     "kendte sårbarheder" = changelog-heuristik, ikke en CVE-database.
  4. Plesk: `autoinstaller --select-release-current --show-upgradable-components --enable-xml-output` (komponenter klar, inkl. plesk/php8.4)
     og `--show-releases --branch release,stable` (ny hovedudgave) — read-only, ~7 s, kører under cbc-security-updates-låsen.
  5. Info: reboot-required, `apt list --upgradable`, seneste kørsel/opgradering fra cbc-security-updates-loggen, egress-filter-status.
- Log `/var/log/cbc-advisory-watch.log`; seneste rapport `/var/lib/cbc-advisory/last-report.txt`.
- Rollback: `rm /etc/cron.d/cbc-advisory-watch`.

## Filer
`/usr/local/sbin/cbc-security-updates.sh`, `/usr/local/sbin/cbc-advisory-watch.sh`, `/etc/cron.d/cbc-security-updates`,
`/etc/cron.d/cbc-advisory-watch`, `/etc/logrotate.d/cbc-security-updates`, kopier i `/root/cbc-hardening-2026-10/stage/updates-2026-10-23/`.
Hurtig status: `tail -20 /var/log/cbc-security-updates.log; cbc-advisory-watch.sh show`
