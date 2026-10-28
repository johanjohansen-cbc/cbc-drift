# CBC Driftsdokumentation — 06 · Runbooks & lærdomme

> Trin-for-trin-runbooks · kendte drifts-gotchas · disaster recovery ·
> break-glass-binding · reference-indeks.
> **Verificeret:** 2026-07-20; ajourført 2026-10-27 med okt. 2026-runbooks og
> -gotchas. Operativ ændringslog (med rollback pr. ændring):
> `/root/cbc-hardening-2026-10/README.md` på serveren.

---

## 1. Runbooks (almindelige opgaver)

### 1.1 Deploy ny kode
Se **04-drift §1**. Kort: `git push both main` (laptop) → på server `deploy-theme.sh`
så `deploy.sh`. **Verificér altid en statisk asset efter deploy** (se §2.1):
```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://event.cbcit.dk/wp-content/themes/cbc-child/style.css  # → 200
```

### 1.2 Rollback
Se **04-drift §1.4**. Scriptet printer den eksakte rollback-kommando ved hver kørsel.

### 1.3 Restore fra backup
Se **05-backup §2**. Plesk Backup Manager (via CF Tunnel) → vælg dato → Restore.

### 1.4 "Sitet er nede"
Følg **`docs/08-hvis-sitet-er-nede.md`** (nødark, også som `.docx` til print).
Kort: tjek mobildata → status.hetzner.com + cloudflarestatus.com → power-cycle i
Hetzner-konsol → vent 10 min → ellers kontakt Johan / break-glass.

### 1.5 Opret ny subscription (HUSK mail-invarianten)
```
Plesk → Subscriptions → Add. EFTERFØLGENDE STRAKS:
plesk bin subscription -u <domain> -mail_service false     # ellers kapres @cbcit.dk-mail!
```
Se **04-drift §3.3** + **00-oversigt §4 (invariant 1)**.

### 1.6 Anvend manuel WP-/plugin-opdatering (majors kun mellem konferencer — 03 §2)
1. Tag et manuelt Hetzner-snapshot (restore-punkt) + DB-dump til `/var/backups/cbc-pre-deploy/`.
2. `su -s /bin/bash <sysuser> -c "…/php -d memory_limit=512M …/wp --skip-themes core update"` (eller plugin/theme update) — på event aldrig via wp-admin (`DISALLOW_FILE_MODS`).
3. `wp cbc db migrate` (hvis CBC-plugin) + `systemctl reload plesk-php84-fpm`.
4. Smoke-test (browser + `wp cron event list` + `wp core verify-checksums --locale=en_US`). Rollback = gendan snapshot / `wp core update --version=X --force` + DB-import.

### 1.7 Tilføj udgående integration fra en ikke-web-proces (ny port)
`cbc_fw` output-chain er **default drop**. Ny udgående port kræver en accept-regel,
ellers fejler forbindelsen stille. Tjek `journalctl -k | grep egress-drop` for drops,
tilføj reglen i `/etc/nftables.d/cbc_fw.nft` (med dead-man), og genindlæs via
`cbc-fw-apply.sh` (se 02-adgang §3.3).

### 1.8 Ny WP-side i plugin'et
Nye sider kræver manuel `ensure-pages` på prod (sider oprettes ikke automatisk ved
deploy). Se plugin-docs / kør plugin'ets side-provisionering efter deploy.

### 1.9 WordPress skal nå et nyt hostnavn (plugin-API, licens-server, webhook)
Web-processerne er allowlistede (02 §3.2). Symptom: plugin melder "kunne ikke
forbinde"/timeout, og den daglige egress-rapport viser drops mod en IP.
```bash
ssh cbc-prod 'journalctl -k --since "-1 day" | grep cbc-egress-drop | grep -oE "DST=[^ ]+" | sort | uniq -c'   # hvilke IP'er?
ssh cbc-prod 'getent hosts <ip>'                                      # hvad er det? (PTR/whois)
ssh cbc-prod 'echo "<hostnavn>   # formaal, dato" >> /etc/cbc-web-egress-hosts.txt && /usr/local/sbin/cbc-web-egress-refresh.sh'
ssh cbc-prod '/usr/local/sbin/cbc-web-egress-mode.sh status'          # allowlist-størrelse steg?
```
Nødbremse ved falske positiver i stor stil: `cbc-web-egress-mode.sh log-only`
(tillader alt, logger stadig) — og tilbage til `enforce` når listen er rettet.

### 1.10 Sikkerhedsopdatering NU (0-day) / se hvad der venter
```bash
ssh cbc-prod '/usr/local/sbin/cbc-security-updates.sh --dry-run'   # viser plan, ændrer intet
ssh cbc-prod '/usr/local/sbin/cbc-security-updates.sh'             # kør nu (ellers næste :45)
ssh cbc-prod '/usr/local/sbin/cbc-advisory-watch.sh show'          # PHP/WP/plugins/Plesk mod upstream
ssh cbc-prod 'tail -20 /var/log/cbc-security-updates.log'
```
Hvis php.net har en patch Plesk endnu ikke har pakket, viser advisory-watch det
("vent på Plesk"); midlertidige PHP-ini-mitigeringer lægges som drop-in i
`/opt/plesk/php/8.4/etc/php.d/zz-cbc-*.ini` + `systemctl restart plesk-php84-fpm`
(domænernes php.ini er autogenererede — redigér dem aldrig).

### 1.11 Card-testing-bølge på cbcit.dk (alarm fra `cbc-woo-order-watch`)
1. WooCommerce → Ordrer: annullér pending-ordrer (eller via wp eval-file:
   `wc_get_orders(status=pending) → update_status('cancelled')`).
2. Tjek at værnene står: CF Security Events (challenge på checkout), Wordfence
   live traffic, `grep cbc-checkout-guard /var/www/vhosts/system/cbcit.dk/logs/error_log`.
3. Skru ned: sænk `CBC_CG_MAX_ORDERS_PER_HOUR` i mu-pluginet, eller slå
   kortbetaling fra midlertidigt i Quickpay-gatewayen (shoppen har ~2 ordrer/år).
4. Orientér Clearhaus/Quickpay (de ser kortforsøgene). Historik: 03 §3.2.

### 1.12 Datagaarden skifter kontor-IP (SFTP virker ikke længere)
Ret `Address` i `Match User datagaardendk`-blokken i `/etc/ssh/sshd_config`
(backup-kopi først), `sshd -t`, `systemctl reload ssh`, verificér med
`sshd -T -C user=datagaardendk,host=x,addr=<ny-ip> | grep -i passwordauth` → yes.
Datagaardens SPF-record viser deres udgående IP (pt. `ip4:87.55.238.154`).

### 1.13 Administrator på event er låst ude af 2FA (mistet telefon/backup-koder)
Verificér identiteten først (ring). Derefter som root:
```bash
ssh cbc-prod 'for k in _two_factor_enabled_providers _two_factor_provider _two_factor_totp_key _two_factor_backup_codes; do su -s /bin/bash event.cbcit.dk_x3pjx5okzbn -c "/opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp --path=/var/www/vhosts/event.cbcit.dk/httpdocs user meta delete <id> $k"; done'
```
I nådeperioden kan vedkommende nu logge ind med password og sætte 2FA op igen.
Efter `CBC_2FA_HARD_DEADLINE` (2026-11-04) afvises login uden 2FA → forlæng
datoen midlertidigt i `wp-content/mu-plugins/cbc-admin-2fa.php` (+ FPM-reload),
lad personen enrolle, og sæt den tilbage. Ny admin: `wp user add-role <id> administrator`
(beholder deltager-rollen) + `retrieve_password('<mail>')` via eval-file sender
WP's standard-nulstillingsmail — **ikke** `wp user reset-password`, der kun
sender en "password ændret"-notits uden link.

### 1.14 Åbn XML-RPC igen (hvis et plugin kræver det)
Fjern `location = /xmlrpc.php …`-blokken i `/var/www/vhosts/system/<dom>/conf/vhost_nginx.conf`
+ `plesk repair web <dom> -y`. Overvej i stedet at allowliste klientens IP i
blokken. Begrund hvorfor — `system.multicall` og pingback er reelle angrebsflader.

---

## 2. Kendte drifts-gotchas (dyrt lærte)

### 2.1 umask-lækage → ustylet site (KRITISK)
Deploy-scripts sætter `umask 077` for fortrolige backups. Den kan lække ind i
`git pull` → opdaterede filer bliver mode `600` → **nginx serverer statiske assets
(CSS/JS/fonte) som en anden bruger end ejeren → HTTP 403 → sitet renderer helt
ustylet, mens PHP-sider loader fint.** Lumsk: curl af HTML'en passerer (inline
styles virker), kun *linkede* assets 403'er. Scripts normaliserer nu perms
(755/644), men **verificér altid en statisk asset efter deploy** (§1.1).

### 2.2 chown-gruppe: plugin ≠ tema
Plugin-mappen ejes `<sysuser>:psaserv`; **temaer ejes `<sysuser>:psacln`**. Ved
manuel rollback: brug `chown --reference=../twentytwentyfive` for temaet, ellers
forkert gruppe → 403.

### 2.3 opcache serverer stale kode
Efter enhver kode-ændring **skal** `systemctl reload plesk-php84-fpm` køres, ellers
serveres den gamle kode fra opcache. Deploy-scripts gør det automatisk.

### 2.4 curl mod prod → 403 uden browser-UA
`event.cbcit.dk`/`cbcit.dk` er bag Cloudflare + origin-guard. En rå `curl` udefra
kan få 403. Brug browser-User-Agent (`-A "Mozilla/5.0"`) ved manuelle tests, eller
test fra selve boksen (loopback er origin-trusted).

### 2.5 `wp` som root forurener perms
Kør ALTID `wp` som sysuser via `su -s /bin/bash <sysuser>` — aldrig som root
(skaber root-ejede cache/transient-filer → efterfølgende 403/skrivefejl).

### 2.6 Mail-kapring ved ny subscription
Se §1.5. Den hyppigste fodbold: glemt `mail_service false` → `@cbcit.dk`-mail
holder op med at virke.

### 2.7 Serveren kan ikke teste sig selv gennem Cloudflare
Lokal DNS peger på egen IP → `curl https://www.cbcit.dk/` fra boksen giver
000/403/421. Test udefra (Johans PC), eller direkte mod FPM med
`curl -k --resolve <host>:443:178.104.70.94 https://<host>/` (= PHP-liveness, ikke
TLS/CF). Scripts (`cbc-security-updates.sh`) bruger sidstnævnte.

### 2.8 Plesk-wrapperen omkring wp-cli
`/usr/local/bin/wp` ignorerer `WP_CLI_PHP_ARGS` → kald altid
`/opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp …`. På
cbcit.dk desuden `--skip-themes` (Flatsome/FCF Pro sprænger 128M). Komplekse
`wp eval`-udtryk gennem `ssh … su -c "…"` knækker på tre lag quoting → skriv en
PHP-fil, `scp` den, kør `wp eval-file`, slet den.

### 2.9 Cloudflare-API: forkert endpoint ligner manglende rettighed
`POST …/rulesets/phases/<phase>/entrypoint/rules` giver `405 code 10405 "Method
not allowed for this authentication scheme"` — det er IKKE en scope-fejl.
Brug `POST /zones/<zone>/rulesets/<ruleset_id>/rules`. Begge rate-limit-slots på
Pro-planen er optaget af api-backenden → brug Managed-Challenge-custom-rules.

### 2.10 Hensigt ≠ konfiguration — verificér skemaer efter ændring
Imunify-scanskemaet blev "sat til dagligt" 23/10-2026, men stod reelt stadig på
månedligt indtil 27/10 (opdaget ved audit). Efter en `config update`: læs værdien
tilbage (`imunify360-agent config show`), og tjek at jobbet faktisk kører
(`malware on-demand list`). Samme princip for timers (`systemctl list-timers`).

### 2.11 Gruppen `psacln` deles af alle sites
Alle tre sysusers har gruppe `psacln` på deres filer. Gruppe-læsbare
`wp-config.php` (664) = DB-password læseligt på tværs af sites. Hold
`wp-config.php` på 600 og docroots uden `g+w` (02 §7.4). Deploy-scripts og
Plesk kan sætte 775/664 ved migrering/Site Import — tjek efter.

> **App-kode-lærdomme** (esc_js/nonce, SQL UTC-skew, tidszone-håndtering m.fl.)
> hører i plugin-repoets `docs/` + projekt-hukommelsen — ikke her. Dette er
> drifts-gotchas.

---

## 3. Disaster recovery
Se **05-backup §2.3** (snapshot → OneDrive → GitHub-mirror) + **08-nødark**.

---

## 4. Break-glass (07) — binding

Break-glass-dokumentet (**07**) beskriver den fulde adgangskæde og HVOR alle
logins/credentials ligger. Det ligger i dette repo (privat GitHub) — det kan det,
fordi det ikke indeholder hemmeligheder.

- **Model:** 07 er **pointer-only** — det indeholder ingen hemmeligheder selv,
  men peger på den delte CBC password manager (Roboform, safe notes) og
  `/root/cbc-deploy-creds.txt` på serveren. Der findes desuden en ledsagende
  **LLM-guide-prompt** (`07-break-glass-llm-guide-prompt.md`) der kan føre en
  efterfølger igennem overtagelsen skridt for skridt.
- **Placering (pr. 2026-07-20, flytning gennemført):** Kanonisk i
  **`drift/07-break-glass-adgang.md` i dette repo** (privat GitHub:
  `johanjohansen-cbc/cbc-drift`) + **print-udgave** (`07-break-glass-adgang.docx`,
  9 sider) til pengeskabet. C:\TMP-arbejdskopierne er slettet efter
  diff-verifikation. ☐ Udestår: Johan printer .docx'en og udskifter det
  forældede print i pengeskabet.
- **Dækning i 07 pr. system** (efter revisionen 2026-07-20 — "☐ vault" =
  beskrevet i 07, men selve credential-entry'en i Roboform skal verificeres/oprettes,
  jf. 07 §2-tjeklisten og §12-drillen):

| System | I 07? | Vault-entry verificeret? |
|---|---|---|
| Hetzner Cloud-konsol (+noVNC-redning) | ✅ §6.1/§8 | ✅ 2026-07-20 |
| SSH (root, nøgle `cbc_hetzner`) | ✅ §2/§4 | ✅ 2026-07-20 |
| Server-creds (`/root/cbc-deploy-creds.txt`) | ✅ §5 | — (på serveren) |
| Cloudflare **"CBC IT v2"** (+ Access/Tunnel) | ✅ §6.2 (rev. 2026-07-20) | ✅ 2026-07-20 |
| CF Tunnel connector-token | ✅ §2 (rev.) | ✅ 2026-07-20 |
| Plesk-admin (`plesk login admin`-metoden) | ✅ §5 | ✅ 2026-07-20 |
| Brevo (SMTP) | ✅ §6.3 | ✅ 2026-07-20 |
| Microsoft 365/OneDrive + **backup-krypteringspassword** | ✅ §6.5 | ✅ 2026-07-20 |
| GitHub-mirror (`johanjohansen-cbc`, nøgle `cbc_github`) | ✅ §6.4 | ✅ 2026-07-20 |
| Domæneregistrar (**Simply.com**) | ✅ §6.6 | ✅ 2026-07-20 |
| **QuickPay** (webshop-betalinger) | ✅ §6.7 | ✅ 2026-07-20 — CBC IT ejer konto+indløseraftale |
| Kent / LB (datagaarden) | ✅ §6.8 | ✅ Kent Grady, kgrady@kobalt.dk |
| **Hetzner-snapshot-token** (DPAPI på Johans PC) + Task Scheduler-job | ✅ §6.1 (tilføjet 2026-10-27) | ☐ Kun på Johans PC — re-udstedes i Hetzner-konsollen ved overdragelse |
| **Cloudflare API-token** `CF_API_TOKEN` (Johans PC) | ✅ §2 (tilføjet 2026-10-27) | ☐ Kun på Johans PC — re-udstedes i CF-dashboardet |
| **Datagaarden SFTP-password** (`datagaardendk`) | ✅ §2/§3 (tilføjet 2026-10-27) | ☐ Verificér at det ligger i vault (ellers: `passwd datagaardendk` som root + giv Datagaarden det nye) |
| **Partner-site-creds** `/root/cbc-partner-sites-creds.txt` | ✅ §5 (tilføjet 2026-10-27) | — (på serveren) |
| **Imunify/Plesk/cron-alarmer → johan@** | ✅ §10 | — (skal omlægges ved overdragelse) |

> **Vault-model:** Roboform; entries som safe notes/gemte logins under servicens
> navn. Verificeret af Johan 2026-07-20 (alle 11 punkter). Næste trin er
> **07 §12-drillen med en KOLLEGA** — Johans egen verifikation beviser at
> nøglerne findes, drillen beviser at en *anden* kan bruge dem. Ingen
> credentials gengives i denne manual.

> **✅ LUKKET 2026-08-27 (var åbent punkt fra 2026-07-20):** Kobalt-aftalens ophør
> 2026-12-31 truede datagaarden.dk's fronting (Kents LB). **Løst før tid:**
> DNS-flip til Cloudflare for SaaS 2026-08-26 (www-CNAME + apex-ANAME →
> `sites.cbcit.dk` hos wwi; custom hostnames i cbcit.dk-zonen), og 2026-08-27 blev
> broen ryddet op: `KENTS-LB-TEMP`-firewall-reglen fjernet, LB-IP'erne ud af
> fail2ban-`ignoreip`, vhost skiftet fra `X-Client-IP` til `CF-Connecting-IP`,
> origin-guard-undtagelsen nedlagt. Kents LB indgår ikke længere i noget
> CBC-setup for denne boks (185.21.232.x-nettet fronter fortsat andre
> cbcit.dk-subdomæner uden for boksen, se 01 §4.2).

---

## 5. Reference-indeks (alle dokumenter)

**Denne driftsmanual** (`_handover/drift/`):
`00-oversigt` · `01-fundament` · `02-adgang-og-sikkerhed` · `03-software-og-sites`
· `04-drift` · `05-backup-og-gendannelse` · `06` (dette).

**Plugin-repoets `docs/`** (applikations-/deploy-nære):
`04-hosting-checklist` · `05-deploy-workflow` · `06-security-pre-deploy` ·
`08-hvis-sitet-er-nede` (+ `.docx`).

**I dette repo:** `07-break-glass-adgang.md` (+ `.docx` til pengeskab) ·
`07-break-glass-llm-guide-prompt.md` · `tools/web-exposure-check.sh`.
Restore-drill-runbook = 05 §2.3/§3.

**På serveren:** `/root/cbc-hardening-2026-10/README.md` (hærdnings-ændringslog
okt. 2026 med rollback pr. punkt, status-kommandoer, `stage/`-kopier af scripts,
`perms-rollback/`, `rollback-step*.sh`).

**På Johans PC:** `C:\Users\JohanJohansen\cbc-ops\` (Hetzner-snapshot-script, log,
DPAPI-token) · Claude Code-projekthukommelse (`…\.claude\projects\…\memory\`,
bl.a. `project_prod_security_audit_2026_10_26.md` = fuld fundliste fra audit).

**Eksternt:** Hetzner-konsol (`console.hetzner.cloud`) · Cloudflare-dashboard
(`dash.cloudflare.com`, CBC IT v2) · Brevo · Quickpay Manager · Plesk-panel
(`https://plesk-event.cbcit.dk` via CF Access/Tunnel).
