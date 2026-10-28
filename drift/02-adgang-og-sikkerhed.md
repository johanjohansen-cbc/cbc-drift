# CBC Driftsdokumentation — 02 · Adgang & sikkerhed

> Adgangsveje · SSH-hærdning · firewall (cbc_fw) · Cloudflare Tunnel/Access ·
> origin-guard · fail2ban/Imunify · applikations-hærdning.
> **Verificeret:** 2026-07-20 via live SSH (`sshd -T`, `nft list`, `systemctl`,
> `cat` af nginx-conf + wp-config); **re-verificeret 2026-10-26/27** (fuld
> read-only audit + Cloudflare-API; nginx-dumps i §7 er fra 2026-10-27).
> Operativ ændringslog med rollback pr. ændring: `/root/cbc-hardening-2026-10/README.md`
> på serveren.

---

## 1. Adgangsveje (oversigt)

| Vej | Endpoint | Autentificering | Noter |
|---|---|---|---|
| **SSH (root)** | `ssh cbc-prod` → port 22 (root) | SSH-nøgle (key-only) | Password-auth slået fra. Alias i laptoppens `~/.ssh/config`. |
| **SFTP partner-dropbox** | port 22, bruger `kent`, chroot `/srv/partner-dump` | Nøgle (`/etc/ssh/authorized_keys.d/kent`), kun `internal-sftp` | Midlertidig (prod-dag 2026-07-10, udløber 2027-01-01). Indhold: site-dumps til Kobalt. Se §2.1. |
| **SFTP Datagaarden** | port 22, bruger `datagaardendk`, chroot `/srv/dg-sftp` (→ datagaarden-docroot) | **Password**, kun `internal-sftp`, **kun fra 87.55.238.154** (Datagaardens kontor, låst 2026-10-26) | Bruges af Datagaardens egne folk til fil-upload (set 18/9 + 7/10-2026). Fra alle andre IP'er: ingen login-metode. Se §2.1. |
| **Plesk-panel** | `https://plesk-event.cbcit.dk` | Plesk-login **bag Cloudflare Access** | Port 8443 er **ikke** firewall-åben — kun via CF Tunnel. Fallback: `ssh -L 8443:127.0.0.1:8443 cbc-prod` → `https://localhost:8443`. |
| **WP-admin (event)** | `https://event.cbcit.dk/wp-admin/` | WP-login (+ magic-link for deltagere på `/login/`) | Bag Cloudflare. `FORCE_SSL_ADMIN=true`. **`wp-login.php` har CF Managed Challenge** (siden 2026-10-26, kun denne host) og brugernavns-enumeration er lukket (§7.2d). |
| **WP-admin (cbcit.dk)** | `wps-hide-login` — login-URL'en er skjult (`/wp-login.php` → 404) | WP-login | Bag Cloudflare. Wordfence + Turnstile på login og checkout. |
| **WP-admin (datagaarden)** | `wps-hide-login` — login-URL'en er skjult | WP-login | Bag Cloudflare (CF for SaaS, siden 2026-08-26). Wordfence aktiv. |
| **Cloudflare-dashboard** | `dash.cloudflare.com` (konto CBC IT v2) | CF-login (2FA) | DNS/WAF/Access/Tunnel-styring. API-token med Zone WAF Edit/Cache Rules/Analytics Read ligger som bruger-miljøvariabel `CF_API_TOKEN` på Johans PC (ingen udløbsdato) — kun host-scopede regler laves via API. |
| **Hetzner-konsol** | `console.hetzner.cloud` | Hetzner-login (2FA) | Power-cycle, snapshots, noVNC. Snapshot-API-token ligger DPAPI-krypteret i `C:\Users\JohanJohansen\cbc-ops\hetzner-token.xml` på Johans PC. |

**Alle logins → break-glass (07).** MFA: Cloudflare + Hetzner har 2FA (07 dækker
recovery-koder). Plesk har MFA-extension installeret, men status for `admin` er
ikke verificeret (panelet kan kun nås via Access/tunnel, så lav risiko).
**WordPress-2FA (audit-fund 3), status 2026-10-28:**
- **event.cbcit.dk: HÅNDHÆVET.** Plugin `two-factor` 0.17.0 + mu-plugin
  `cbc-admin-2fa.php` (§7.2d): kun TOTP + backup-koder; administratorer uden 2FA
  kan kun nå deres profilside; fra **2026-11-04 23:59** afvises login uden 2FA.
  Admins er nu `cbcadmin` (johan@), `anja@cbcit.dk`, `jan@cbcit.dk` — alle også
  `cbc_participant`. `janadmin` (privat mail) er slettet. Magic-link afviser
  privilegerede konti (`Magic_Link::PRIVILEGED_CAP = edit_posts`), så admins kan
  kun logge ind via `wp-login.php` (CF-challenge) = password + TOTP. Enrollment:
  cbcadmin ✅ (28/10); anja/jan afventer (reset-links sendt 28/10).
- **cbcit.dk (johan + Kent) og datagaarden.dk (7 ansatte, alle administrator):
  ÅBENT.** Wordfence Login Security-modulet i Wordfence er installeret men ikke
  aktiveret. Næste trin efter event.

---

## 2. SSH-hærdning

Effektiv `sshd`-config (fra `sshd -T`, 2026-07-20):

| Indstilling | Værdi | Betydning |
|---|---|---|
| `port` | 22 | Standard, firewall-åben |
| `permitrootlogin` | `without-password` | Root **kun** med nøgle — aldrig password |
| `passwordauthentication` | `no` | Ingen password-login overhovedet |
| `pubkeyauthentication` | `yes` | Nøgle-baseret |
| `kbdinteractiveauthentication` | `no` | — |
| `permitemptypasswords` | `no` | — |
| `x11forwarding` | `no` | — |

- Drop-in `/etc/ssh/sshd_config.d/99-cbc-hardening.conf` sætter desuden
  `LoginGraceTime 30`, `MaxAuthTries 3`, `ClientAliveInterval 300`,
  `ClientAliveCountMax 2`. `AllowTcpForwarding yes` er bevaret (SSH-tunnel til Plesk).
- **Laptop-adgang:** `ssh cbc-prod` bruger nøgle `cbc_hetzner` (ed25519, ingen
  passphrase — bevidst, for non-interaktive deploy-scripts) via `~/.ssh/config`.
  Nøglen skal beskyttes; genskabelse ved laptop-tab → se 07 + plugin-docs §14.
- **Brute-force:** fail2ban-jail `ssh` er aktiv (se §5).

### 2.1 SFTP-brugere (Match-blokke i `/etc/ssh/sshd_config`, verificeret 2026-10-26)

To ikke-root-brugere kan logge ind over port 22 — begge kun SFTP i chroot, ingen
shell, ingen forwarding:

| Bruger | Chroot | Auth | Formål / status |
|---|---|---|---|
| `kent` (uid 10003, `/usr/sbin/nologin`) | `/srv/partner-dump` (undermapper `cbcit.dk/`, `datagaarden.dk/`, 700 kent) | **Nøgle-only** (`AuthorizedKeysFile /etc/ssh/authorized_keys.d/kent`), `ForceCommand internal-sftp -u 0077` | Midlertidig partner-dropbox til Kobalt (site-dumps fra 2026-07-15). Kommentar i sshd_config: udløber 2027-01-01 → **slet bruger + Match-blok + `/srv/partner-dump` ved årsskiftet.** |
| `datagaardendk` (Plesk-sysuser, `/bin/false`) | `/srv/dg-sftp` (bind til `/var/www/vhosts/datagaarden.dk/httpdocs`) | **Password** (`PubkeyAuthentication no`), `ForceCommand internal-sftp -u 0022`, **`Match User datagaardendk Address 87.55.238.154`** | Datagaardens egen fil-upload (fx `/Support/`-materiale). Siden 2026-10-26 kun fra deres kontor-IP; en efterfølgende catch-all `Match User datagaardendk` sætter Password/Pubkey/KbdInteractive = no for alle andre kilder. Backup før ændringen: `/etc/ssh/sshd_config.pre-dgip-20261026`. **Skifter Datagaarden IP, skal `Address` rettes** (så `sshd -t` + `systemctl reload ssh`). |

> Verificér effektiv config for en bruger fra en given IP:
> `sshd -T -C user=datagaardendk,host=x,addr=87.55.238.154 | grep -iE "passwordauth|chroot"`.

---

## 3. Firewall — nftables `cbc_fw`

Boksen bruger **hverken ufw eller firewalld** (begge inaktive) — i stedet en
custom nftables-tabel `cbc_fw` med **både input- og egress-filtrering**.

### 3.1 Input-chain (policy DROP)

```
iif "lo" accept
ct state established,related accept
ct state invalid drop
icmp / ipv6-icmp accept
tcp dport 22 accept                          # SSH — offentlig, key-only
tcp dport 80 counter accept                  # ACME-HTTP01-OPEN (2026-08-17)
ip  saddr @cf4 tcp dport { 80, 443 } accept  # web kun fra Cloudflare (v4)
ip6 saddr @cf6 tcp dport { 80, 443 } accept  # web kun fra Cloudflare (v6)
```

(Afspejler live-ruleset pr. 2026-10-26 — uændret siden 2026-08-27. Sets:
`cf4` 15 ranges, `cf6` 7 ranges, auto-opdateret søndag 04:30 af
`cbc-fw-refresh.timer`.)

- `@cf4`/`@cf6` = **alle Cloudflare IP-ranges** (named sets). **443** er dermed
  låst til Cloudflare — ingen kan ramme HTTPS-origin direkte udenom CF.
- **Port 80 er åben for ALLE kilde-IP'er siden 2026-08-17** (`ACME-HTTP01-OPEN`):
  Let's Encrypt publicerer ikke sine validerings-IP'er, så HTTP-01-fornyelse
  kræver åben port 80. Port 80 serverer kun redirects + ACME-challenges.
- **`KENTS-LB-TEMP` (185.21.232.10-12 på 443) er FJERNET 2026-08-27** efter
  DNS-flip af datagaarden.dk til CF for SaaS 2026-08-26 (backup af den gamle fil:
  `/etc/nftables.d/cbc_fw.nft.pre-lb-cleanup`).
- **8443 (Plesk) er bevidst IKKE i input** → panelet kan kun nås via CF Tunnel.

### 3.2 Output-chain (policy DROP — egress-hærdning i to lag)

**Lag 1 — alle processer (siden 2026-06-05):** kun disse udgående forbindelser
tillades; alt andet logges + droppes:

```
lo, established/related, icmp
meta skuid { 10000, 10001, 10002 } jump web_egress   # web-uids: event/cbcit/datagaarden → lag 2
udp 53 / tcp 53   (DNS)
udp 123           (NTP)
udp 67            (DHCP)
tcp 80, 443, 587  (web-opdateringer + Brevo SMTP-submission)
udp/tcp 7844      (Cloudflare Tunnel til CF's edge)
→ resten: rate-limited log "cbc_fw egress-drop:" + drop
```

**Lag 2 — `web_egress`-chain for de tre PHP-FPM-brugere (blast-radius-værn,
log-only 2026-10-22 → ENFORCE 2026-10-23):** WordPress-processerne må kun nå
allowlistede destinationer, så et kompromitteret site ikke frit kan hente
payloads, exfiltrere eller fungere som C2-klient:

```
ip  daddr @web_allow4     tcp dport { 80, 443, 587 } accept   # oploeste hostnavne (v4)
ip6 daddr @web_allow6     tcp dport { 80, 443, 587 } accept
ip  daddr @web_allow_net4 tcp dport { 443, 587 } accept       # udbyder-ranges (Google, Meta)
ip6 daddr @web_allow_net6 tcp dport { 443, 587 } accept
udp dport 123 accept                                          # web-ntp
counter "cbc-egress-hits" → log "cbc-egress-drop" + drop     # cbc-egress-mode: enforce
```

| Komponent | Hvad |
|---|---|
| Allowlist (hostnavne) | `/etc/cbc-web-egress-hosts.txt` (~70 hosts: wordpress.org-API, plugin-leverandører, Brevo, Quickpay, Cloudflare, Google/Meta-API'er m.fl.) |
| Allowlist (ranges) | `/etc/cbc-web-egress-ranges.txt` (~720 prefixes: Google `goog.json` + Meta AS32934), hentet søndag 04:50 af `cbc-web-egress-ranges.timer` via `cbc-web-egress-ranges-fetch.sh` (fail-safe: beholder gammel fil + mailer ved fejl) |
| Opløsning → nft-sets | `cbc-web-egress-refresh.sh` hver time (`cbc-web-egress-refresh.timer`, også 2 min efter boot); elementer med 8 dages timeout; persisteres i `/etc/nftables.d/cbc_web_egress_elements.nft`, som `cbc-fw-apply.sh` genindlæser ved boot |
| Tilstand | `cbc-web-egress-mode.sh status|log-only|enforce` — skifter atomisk mellem log-only (tillad + log) og enforce (drop), og opdaterer regelfilen. **Rollback ved falsk positiv = `cbc-web-egress-mode.sh log-only`.** |
| Rapport | `cbc-egress-report.sh` dagligt 06:55 mailer johan@ en opsummering af drops (sender ALTID, så udebleven mail = fejl) |
| Kendte, bevidst afviste destinationer | `api.bitbucket.org` (WebAppick-feed-plugin "ringer hjem"); enkelte Hetzner-/ukendte IP'er i lav volumen fra ikke-web-processer — følges i rapporten |

> **Konsekvens for drift:** et nyt plugin, en ny licens-server eller et nyt API
> kaldt fra WordPress bliver **tavst droppet**, indtil hostnavnet er tilføjet i
> `cbc-web-egress-hosts.txt` + `cbc-web-egress-refresh.sh` er kørt (06 §1.9).
> En ny udgående integration fra en *ikke*-web-proces på en anden port kræver
> stadig en accept-regel i `output`-chain. Fejlsøgning:
> `journalctl -k | grep -E "egress-drop|cbc-egress-drop"`.

### 3.3 Hvor reglerne bor + ekstra firewall-lag

- `nft list table inet cbc_fw` viser den kørende tabel; regel-filen er
  **`/etc/nftables.d/cbc_fw.nft`** (chains + statiske regler) +
  **`cbc_web_egress_elements.nft`** (sidst kendte allowlist-IP'er). Daterede
  backups ligger ved siden af (`.pre-egress`, `.pre-acme80`, `.pre-lb-cleanup`,
  `.pre-mode-2026…`; `.fallback` = den helt gamle 80/443-åbne version). Boot-
  persistens: `cbc-fw.service` → `/usr/local/sbin/cbc-fw-apply.sh`.
- **`cbc-fw-refresh.sh`** (timer søndag 04:30) henter CF's IP-liste og
  opdaterer KUN `cf4/cf6`-elementerne i filen (omskrevet 2026-10-22, så
  output-/web_egress-chains ikke længere kan forsvinde ved en CF-ændring).
- **Dead-man switch-disciplin:** enhver firewall-ændring køres med en
  `systemd-run --on-active=300 … nft delete table inet cbc_fw`-sikring FØR apply
  (test frisk SSH, annullér derefter) — se 07 §9.
- **Hetzner Cloud Firewall `cbc-edge`** (id 11085732) ligger som ekstra lag FORAN
  boksen (styres i Hetzner-konsollen, påvirker ikke noVNC). Regler (sat
  2026-06-05): inbound tillad KUN tcp 22, 80, 443 + ICMP fra `0.0.0.0/0` og
  `::/0`; alt udgående tilladt. Bevidst grovkornet — den præcise CF-only-lås på
  443 ligger i host-nftables (auto-opdateret), så CF-IP-listen kun vedligeholdes
  ét sted. Ingen hcloud-token gemt på boksen (ad hoc-token, slettes bagefter).

---

## 4. Cloudflare Tunnel (adgang til Plesk-panelet)

- **`cloudflared`** kører som systemd-service (named tunnel, token-baseret;
  `tunnel run --token …`). Tunnel-ID og account-tag ligger i tokenet; **selve
  tokenet er en credential → 07**, gengives ikke her.
- Da 8443 ikke er firewall-åben, er tunnellen den **eneste** vej til Plesk-panelet
  udefra. Tunnellen egress'er til CF på port 7844 (tilladt i cbc_fw output).
- **Ingress-config ligger på Cloudflare-siden** (named tunnel med remote config —
  der er ingen lokal `/etc/cloudflared/config.yml`).
- **Tunnel `cbc-plesk`** (verificeret i Cloudflare One-dashboard 2026-07-20):

| | |
|---|---|
| Tunnel-ID | `2bf08ca3-2a47-41f4-af1c-f5925c12854a` |
| Connector | kører på `server.cbcit.dk` (IPv6-udgående), cloudflared 2026.10.4 (pr. 2026-10-26; opdateres nu automatisk af `cbc-security-updates.sh`), datacenter `fra`, status Healthy |
| Route | `plesk-event.cbcit.dk` `/*` → **`https://localhost:8443`** (Plesk) |
| Catch-all | `http_status:404` (alt andet end den publicerede route afvises) |

  Plesk-panelet nås altså på **`https://plesk-event.cbcit.dk`** — bag Access.

### 4.1 Cloudflare Access (verificeret i Cloudflare One-dashboard 2026-07-20)

| | |
|---|---|
| Team-domæne | `fancy-sound-8625.cloudflareaccess.com` |
| Access-app | **"CBC Plesk Panel"** (self-hosted) → destination `plesk-event.cbcit.dk` |
| Policy | **"Allow cbcit.dk"** (Allow, 1 regel, legacy-format — reglen tillader efter navnet at dømme `@cbcit.dk`-mails; ‹verificér regel-indholdet ved lejlighed›) |
| Session-varighed | 24 timer |
| Identity providers | "Accept all available identity providers" = On (default: One-time PIN via e-mail) |
| Kapacitet | 1 aktiv bruger af 50 (free seats) |

- Historik: CF Access sat op på kontoen "CBC IT v2" på prod-dagen 2026-07-10 —
  verificér løbende at policyen stadig peger på de rette personer.

### 4.2 Cloudflare WAF (verificeret via CF-API 2026-10-26; zone `cbcit.dk`, id `8a814aaf…`)

| Lag | Konfiguration |
|---|---|
| **Managed rules** | Cloudflare Managed Ruleset: **aktiv** (hele zonen) · **OWASP Core Ruleset: aktiv** med undtagelse `not host in {api,legacy} and not path starts_with /wp-admin/` · Exposed Credentials Check + Normalization + DDoS L7 (CF-default) |
| **Super Bot Fight Mode** | Aktiv (Pro-plan) — custom skip-regel "Exempt api + legacy from Super Bot Fight Mode" (hostname `api.cbcit.dk`/`legacy.cbcit.dk`) |
| **Custom rules (ruleset `00b410ad…`)** | **(a)** `174e59a6…` **Managed Challenge på WooCommerce-checkout** (2026-10-21, card-testing-værn): host `cbcit.dk`/`www.cbcit.dk` og path `/checkout*` eller query `wc-ajax=checkout` eller Store-API-checkout, undtagen verificerede bots. **(b)** `dd08cdde…` **Managed Challenge på `/wp-login.php` for `event.cbcit.dk`** (2026-10-26, audit-fund 4): GET+POST, undtagen verificerede bots — browseren løser challenge ved GET (clearance 30 min) før POST; bots uden clearance stoppes ved kanten. |
| **Rate limiting** | 2 regler (begge slots på Pro-planen er brugt): "Auth endpoint rate limit" (`/auth/`, api-backend) + "API flood ceiling per IP" (`api.cbcit.dk`). **Ingen slot tilbage til denne boks** — derfor bruges Managed-Challenge-custom-rules i stedet. |
| **Access** | App "CBC Plesk Panel" → `plesk-event.cbcit.dk` (se §4.1; verificeret 2026-10-27: 302 → `fancy-sound-8625.cloudflareaccess.com`) |

> Regler oprettes via API med `POST /zones/{zone}/rulesets/{ruleset_id}/rules`
> (IKKE `.../phases/{phase}/entrypoint/rules`, som giver 405 code 10405 og ligner
> en manglende scope). Token: `CF_API_TOKEN` i Johans bruger-miljø (02 §1).
> **Zonen deles med ~18 andre CBC-sites → kun host-scopede regler, aldrig zone-wide ændringer.**

---

## 5. Netværks-/host-sikkerhed på boksen

| Lag | Status (2026-10-26) |
|---|---|
| **fail2ban** | Aktiv — 13 jails: `ssh`, `recidive`, `plesk-apache`, `plesk-apache-badbot`, `plesk-wordpress`, `plesk-postfix`, `plesk-dovecot`, `plesk-proftpd`, `plesk-panel`, `plesk-roundcube`, `plesk-modsecurity`, `plesk-one-week-ban`, `plesk-permanent-ban`. `recidive` holder typisk 5–10 IP'er bannet. |
| **Imunify** | ImunifyAV 8.10.1 (Plesk-extension `imunify360`). **Malware-scan af alle vhosts DAGLIGT 03:00** (`MALWARE_SCAN_SCHEDULE interval=day` — sat 2026-10-27; indtil da stod skemaet reelt på månedligt trods hensigten 23/10). Realtime inotify-scan + Proactive Defense (`php_immunity`) aktive. Seneste fulde scans 22+23/10: 0 fund. |
| **ModSecurity** | Aktiv (`SecRuleEngine On` i Apache; fail2ban-jail `plesk-modsecurity` har bannet ~90 IP'er i alt) |
| **Cloudflare WAF** | Se §4.2 (Managed + OWASP + 2 custom Managed-Challenge-regler) |
| **Wordfence** | Aktiv på `cbcit.dk` (9.0.2; `howGetIPs=HTTP_CF_CONNECTING_IP`, rate-limits throttle 240/120/60; sat 2026-10-21) og `datagaarden.dk` (9.0.2). **Ikke** på event (pluginet har egen login-rate-limit). Wordfence Login Security/2FA er IKKE aktiveret på cbcit/datagaarden (åbent — se §1). |
| **2FA (event)** | `two-factor` 0.17.0 + mu-plugin `cbc-admin-2fa.php`: påkrævet for rollen administrator (TOTP + backup-koder), hård deadline 2026-11-04. Nulstil en låst admin: `wp user meta delete <id> _two_factor_enabled_providers` + `_two_factor_provider` + `_two_factor_totp_key` + `_two_factor_backup_codes` (06 §1.13). |
| **PHP `disable_functions`** | Alle tre FPM-pools (per-domæne Plesk PHP-settings, siden 2026-10-22): `opcache_get_status,exec,shell_exec,system,passthru,proc_open,popen,pcntl_exec`. `open_basedir` = egen vhost + `/tmp`. `expose_php=Off`, `allow_url_include=Off`. **Sættes via Plesk pr. domæne, ikke php.d** (domænernes php.ini autogenereres); globale ini-ændringer = drop-in i `/opt/plesk/php/8.4/etc/php.d/` (fx `zz-cbc-upload-progress.ini`, 21/10). |
| **nginx request-grænser** | Alle tre vhosts (2026-10-22): `client_max_body_size` 8M (Plesk per-domæne), `client_body_timeout`/`client_header_timeout` 15s, `client_header_buffer_size` 1k, `large_client_header_buffers` 2 8k (§7.2). |
| **WP-integritet** | `cbc-wp-integrity.timer` **dagligt 05:15** (drop-in `daily.conf`, siden 2026-10-23; var ugentlig): core+plugin-checksums alle 3 sites, mailer kun ved afvigelse. Log `/var/log/cbc-wp-integrity.log`. |
| **Advisory-watch** | `cbc-advisory-watch.sh` dagligt 07:15 (PHP/WP/plugins/Plesk mod php.net, api.wordpress.org, Plesk-autoinstaller) + ugentlig "alt OK"-mail mandag 07:30. Log `/var/log/cbc-advisory-watch.log`. |
| **Ordre-velocity (cbcit.dk)** | `cbc-woo-order-watch.sh` hver time :07 — mailer ved > 5 ordrer/time (card-testing-værn, 2026-10-21). |

> **Strukturelt hul (audit 2026-10-26):** al overvågning er selvrapporterende fra
> boksen (mails fra serveren). En angriber med root kan tie den. Der findes ingen
> ekstern uptime-/dead-man-monitor. Undtagelsen er Hetzner-snapshot-mailen, der
> sendes fra Johans PC.

---

## 6. Origin-bypass-værn (`cbc-origin-guard.conf`)

Fil: `/etc/nginx/conf.d/cbc-origin-guard.conf` (oprettet 2026-07-20 i forbindelse
med datagaarden-LB-sporet — beholdt permanent efter LB-broens nedlukning).

- **Problem det løste oprindeligt:** mens firewallen var åben for Kents LB på 443,
  kunne LB-IP'erne teknisk sende *enhver* Host-header til origin — også
  `Host: event.cbcit.dk`. Firewallen kan ikke filtrere på Host. I dag fungerer
  guarden som generelt bælte-og-seler-lag oven på firewallen (fanger fx trafik
  der slipper ind via den ACME-åbne port 80 og videresendes internt).
- **Mekanik:** en nginx `geo`-blok på `$realip_remote_addr` (den **rå** TCP-peer,
  upåvirket af `set_real_ip_from`) sætter `$cbc_origin_not_trusted = 1` for enhver
  peer der **ikke** er Cloudflare, loopback eller egen origin-IP.
- **Håndhæves** i `event.cbcit.dk` + `cbcit.dk` via deres nginx additional
  directives, og **siden 2026-08-27 også i `datagaarden.dk`** (vhost_nginx.conf,
  sammen med CF-real-ip-blokken): `if ($cbc_origin_not_trusted) { return 403; }`.
  Den historiske LB-undtagelse er dermed nedlagt.

> **Rør ikke** ved geo-listen uden at opdatere den mod Cloudflares aktuelle
> IP-ranges (samme liste som cbc_fw's `@cf4/@cf6`).

---

## 7. Applikations-hærdning (alle tre sites)

### 7.1 wp-config.php (event verificeret 2026-07-20; alle tre re-verificeret 2026-10-26)

`event.cbcit.dk`:
```php
$table_prefix = 'wp<custom>_';        // ikke standard 'wp_' (mild obscurity)
define('WP_DEBUG', false);
define('WP_DEBUG_DISPLAY', false);
define('FORCE_SSL_ADMIN', true);
define('DISALLOW_FILE_EDIT', true);   // ingen theme/plugin-editor i wp-admin
define('DISALLOW_FILE_MODS', true);   // ingen install/update via UI (deploy via git)
define('WP_AUTO_UPDATE_CORE', 'minor');
define('DISABLE_WP_CRON', true);      // system-cron i stedet (se 04-drift)
define('WP_POST_REVISIONS', 10);
```

`cbcit.dk` + `datagaarden.dk` (prefix `wp_`): `DISALLOW_FILE_EDIT=true`,
`FORCE_SSL_ADMIN=true`, `DISABLE_WP_CRON=true` (system-cron siden okt. 2026),
`WP_DEBUG=false`. **`DISALLOW_FILE_MODS` er IKKE sat** — bevidst, så plugins kan
auto-opdatere sig selv (de fleste har auto-update slået til). `users_can_register=0`
på alle tre.

### 7.2 nginx additional directives (event.cbcit.dk)

- **Security-headers** (alle `always`): `Strict-Transport-Security`
  (`max-age=31536000; includeSubDomains`), `X-Content-Type-Options: nosniff`,
  `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: strict-origin-when-cross-origin`.
- **Anti-indeksering:** `X-Robots-Tag: noindex, nofollow` (server-niveau, dækker
  også PDF/wp-json/assets) + WP `blog_public=0` (verificeret).
- **Dev-fil-beskyttelse (S2):** `docs/`, `tools/`, `tests/`, `*.md`, `*.sh`,
  `*.lock`, `*.dist`, `composer.json` i plugin-dir → `return 404`.
- **Real visitor IP:** `set_real_ip_from` alle CF-ranges + `real_ip_header
  CF-Connecting-IP` (så logs/rate-limits ser den ægte besøger, ikke CF).
- **Origin-guard:** `if ($cbc_origin_not_trusted) { return 403; }` (se §6).
- **Request-grænser (2026-10-22):** body/header-timeouts 15 s, små header-buffere
  (PHP-advisory CVE-2026-109618: "enforce request size at the frontend").
  `client_max_body_size` 8M sættes pr. domæne via Plesk
  (`plesk bin subscription --update-web-server-settings <dom> -nginx-client-max-body-size 8388608`),
  ikke her (duplikat afvises af nginx).
- **XML-RPC lukket (2026-10-26):** `location = /xmlrpc.php { return 403; }` —
  fjerner `system.multicall`-brute-force og pingback-SSRF. Ingen klienter bruger det.

**Verbatim kilde** (dump af `/var/www/vhosts/system/event.cbcit.dk/conf/vhost_nginx.conf`,
2026-10-27 — det Plesk genererer af "Additional nginx directives"). Ved migrering
væk fra Plesk: kopiér blokken ind i den nye vhost/server-blok som den står
(origin-guard-linjen kræver desuden geo-blokken fra §6; real_ip-listen skal
holdes ajour med Cloudflares offentliggjorte ranges):

```nginx
# CBC E-4 — HTTP security-headers
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

# CBC 10.11 — anti-indeksering (semi-privat site, må ikke i søgeresultater).
# Server-niveau noindex der også dækker ikke-HTML (Dompdf-PDF, wp-json, assets)
# og overlever plugin/tema-ændringer. Supplerer WP blog_public=0 (meta + robots.txt).
add_header X-Robots-Tag "noindex, nofollow" always;

# CBC E-2 — S2-hardening: blokér interne dev-filer i plugin-dir
location ~* ^/wp-content/plugins/cbc-event-planner/(docs|tools|tests)/ { return 404; }
location ~* ^/wp-content/plugins/cbc-event-planner/.*\.(md|sh|lock|dist)$ { return 404; }
location ~* ^/wp-content/plugins/cbc-event-planner/composer\.json$ { return 404; }

# CBC proxy-migration (2026-06-05) — restore real visitor IP behind Cloudflare
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 131.0.72.0/22;set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;real_ip_header CF-Connecting-IP;

# CBC origin-bypass-vaern (geo i /etc/nginx/conf.d/cbc-origin-guard.conf)
if ($cbc_origin_not_trusted) { return 403; }

# CBC blast-radius 2026-10-22 — request-graenser (PHP-advisory CVE-2026-109618: "enforce request
# size at the frontend"). client_max_body_size (8M) styres pr. domaene via Plesk:
# plesk bin subscription --update-web-server-settings <dom> -nginx-client-max-body-size 8388608 (duplikat her afvises af nginx).
client_body_timeout 15s;
client_header_timeout 15s;
client_header_buffer_size 1k;
large_client_header_buffers 2 8k;

# CBC 2026-10-26: xmlrpc.php lukket (system.multicall-brute-force + pingback-SSRF; ingen legitime klienter). Rollback: fjern blokken + plesk repair web event.cbcit.dk -y
location = /xmlrpc.php { access_log off; return 403; }
```

> **Vedligehold:** ændres direktiverne i Plesk, opdatér dumpet her i samme
> ombæring. Anvend ændringer med `plesk repair web <domæne> -y` (regenererer +
> reloader nginx). Verificér effekten udefra med `tools/web-exposure-check.sh` (se §8).

### 7.2b nginx additional directives (datagaarden.dk) — siden 2026-08-27, udvidet okt. 2026

Efter DNS-flippet til CF for SaaS (2026-08-26) fik `datagaarden.dk` samme
real-ip- og origin-guard-opsætning som event/cbcit. **Verbatim kilde**
(`/var/www/vhosts/system/datagaarden.dk/conf/vhost_nginx.conf`, 2026-10-27;
backup af Kents-LB-versionen i `/root/vhost_nginx.conf.datagaarden.pre-cf-flip`,
backup før xmlrpc-blokken `.pre-xmlrpc-20261026`): CF-`set_real_ip_from`-listen
(22 linjer, identisk med event-blokken) + `real_ip_header CF-Connecting-IP;` +
origin-guard-linjen + **samme request-grænse-blok og `xmlrpc.php`-403-blok som
event ovenfor** (kommentaren nævner `plesk repair web datagaarden.dk -y`).

Bemærk: IDN-aliasset `xn--datagrden-92a.dk` har sin egen Plesk-genererede
server-blok, der KUN 301-redirecter til `https://datagaarden.dk` — den har
bevidst hverken real-ip eller guard (serverer intet indhold).

### 7.2c nginx additional directives (cbcit.dk) — siden 2026-10-21

`/var/www/vhosts/system/cbcit.dk/conf/vhost_nginx.conf` (2026-10-27; backups
`.pre-realip-20261021`, `.pre-xmlrpc-20261026`): CF-`set_real_ip_from`-listen
(21 linjer, kopi af event-blokken — **nødvendig for at Woo/Wordfence/IP-blokering
ser den ægte kunde-IP**; manglede før card-testing-angrebet) +
`real_ip_header CF-Connecting-IP;` + origin-guard-linjen + request-grænse-blok +
`xmlrpc.php`-403-blok. Apache fuldfører kæden med `mod_remoteip` (Plesk-default).

### 7.2d Must-use-plugins (ligger i `wp-content/mu-plugins/`, uden for git, ejet af sysuser 644)

| Site | Fil | Gør |
|---|---|---|
| `cbcit.dk` | `cbc-checkout-guard.php` (2026-10-21, card-testing-værn) | Store-API-checkout → 403; klassisk checkout kræver same-origin `Referer` + velocity-loft **3 ordrer/time/IP og 12 forsøg/time/IP** (transients, admins undtaget). Logger `[cbc-checkout-guard]` i vhost-`error_log`. |
| `event.cbcit.dk` | `cbc-no-user-enum.php` (2026-10-26, audit-fund 4) | Anonyme får 404 på REST `/wp/v2/users*`, `?author=N` (ingen kanonisk redirect) og forfatterarkiver; generisk login-fejltekst. Indloggede (Gutenberg, brugerliste) uberørte. Rollback: slet filen + `systemctl reload plesk-php84-fpm`. |
| `event.cbcit.dk` | `cbc-admin-2fa.php` (2026-10-28, audit-fund 3) | Kræver Two-Factor-pluginet. Filter `two_factor_providers` → kun TOTP + backup-koder. Filter `two_factor_is_required_for_user` → true for administratorer med provider, og for ALLE administratorer efter `CBC_2FA_HARD_DEADLINE` (2026-11-04 23:59). `admin_init`: administrator uden 2FA redirectes til `profile.php` (undtagen ajax/cron/CLI/admin-post). `admin_notices`: dansk vejledning. Rollback: slet filen + FPM-reload (så gælder kun pluginets frivillige 2FA). |

> mu-plugins følger med Plesk-backuppen (ligger i docroot) men **ikke** med
> plugin-repoets deploy. Ved genopbygning uden backup: genskab fra
> `/root/cbc-hardening-2026-10/README.md`-beskrivelsen (kildekopier ligger ikke i git).

### 7.2e Øvrig app-hærdning cbcit.dk (webshop, 2026-10-21 efter card-testing-angreb 18–21/10 med 272 svindelordrer)

- Plugin `simple-cloudflare-turnstile` (CAPTCHA) på Woo-checkout, pay-for-order,
  Woo-login og WP-login (nøgler sat af Johan).
- Quickpay-gateway: `quickpay_cardtypelock=3d-creditcard` (tvungen 3-D Secure)
  og `quickpay_payment_window_timeout=600` (betalingslink udløber efter 10 min).
  Svindel-filter tilpasset i Quickpay Manager (Indstillinger → Svindel-filter).
- CF Managed Challenge på checkout (§4.2 a) + Wordfence real-IP/rate-limits (§5).
- Overvågning: `cbc-woo-order-watch.sh` (§5). Baseline for shoppen: ~2 ægte ordrer/år.

### 7.3 `.git`-eksponering (S1) — verificeret lukket

`.git/` i plugin-mappen returnerer **403** udefra (testet via CF 2026-07-20).
Blokeres på origin-niveau via Plesk's genererede nginx-config (dot-fil-deny) +
Cloudflare. Defense-in-depth: selv uden reglen kan origin ikke nås direkte
(firewall + origin-guard).

### 7.4 Fil-permissions

- Web-filer: dirs `755`, filer `644` (deploy-scripts normaliserer dette — kritisk
  pga. en umask-lærdom, se 06-runbooks §gotchas).
- `wp-config.php`: `600` på **alle tre** sites. Backup-mappe
  `/var/backups/cbc-pre-deploy`: `700`.
- **2026-10-26:** `cbcit.dk` og `datagaarden.dk` var `775/664` i hele docroot
  (30k + 54k filer; datagaardens `wp-config.php` var 664). Gruppen `psacln` deles
  af alle tre sites' PHP-brugere, så ét kompromitteret site kunne læse de andres
  DB-passwords (`open_basedir` var eneste værn). Rettet med `chmod -R g-w` +
  `wp-config.php 600`; fuld rettighedsliste fra før ligger i
  `/root/cbc-hardening-2026-10/perms-rollback/<domæne>-pre-20261026.txt.gz`.
  Datagaardens SFTP-upload kører med `-u 0022` og ejer selv filerne, så
  skrive-flowet er uberørt (testet).
- Ingen world-writable filer, ingen PHP i `uploads/` (kun plugin-stubs) på nogen af
  siderne (audit 2026-10-26).

---

## 8. Verifikations-kommandoer

```bash
ssh cbc-prod 'sshd -T | grep -E "permitroot|passwordauth|pubkey"'
ssh cbc-prod 'nft list table inet cbc_fw'
ssh cbc-prod 'systemctl is-active cloudflared fail2ban; fail2ban-client status'
ssh cbc-prod 'cat /etc/nginx/conf.d/cbc-origin-guard.conf'
ssh cbc-prod 'curl -sI -A Mozilla https://event.cbcit.dk/wp-content/plugins/cbc-event-planner/.git/config | head -1'  # → 403
bash drift/tools/web-exposure-check.sh   # ekstern S2-verifikation: docs/ m.m. blokeret, site OK (exit 0 = alt grønt)

# Okt. 2026-lagene:
ssh cbc-prod 'sshd -T -C user=datagaardendk,host=x,addr=1.2.3.4 | grep -i passwordauth'   # → no (kun kontor-IP må)
ssh cbc-prod '/usr/local/sbin/cbc-web-egress-mode.sh status'                               # → enforce + tællere
ssh cbc-prod 'grep -H disable_functions /opt/plesk/php/8.4/etc/php-fpm.d/*.dk.conf'
ssh cbc-prod 'imunify360-agent config show | grep -oE "\"MALWARE_SCAN_SCHEDULE\": \{[^}]*\}"'  # → interval day
for h in event.cbcit.dk www.cbcit.dk www.datagaarden.dk; do curl -s -o /dev/null -A Mozilla -w "$h xmlrpc=%{http_code}\n" -X POST -d '<methodCall/>' https://$h/xmlrpc.php; done   # → 403 ×3
curl -s -o /dev/null -A Mozilla -w '%{http_code}\n' 'https://event.cbcit.dk/?author=1'     # → 404 (ingen brugernavns-redirect)
curl -s -o /dev/null -A Mozilla -D - https://event.cbcit.dk/wp-login.php | grep -i cf-mitigated   # → challenge
```
