# CBC Driftsdokumentation — 02 · Adgang & sikkerhed

> Adgangsveje · SSH-hærdning · firewall (cbc_fw) · Cloudflare Tunnel/Access ·
> origin-guard · fail2ban/Imunify · applikations-hærdning.
> **Verificeret:** 2026-07-20 via live SSH (`sshd -T`, `nft list`, `systemctl`,
> `cat` af nginx-conf + wp-config). Cloudflare Access/WAF markeret **‹CF-DASHBOARD›**.

---

## 1. Adgangsveje (oversigt)

| Vej | Endpoint | Autentificering | Noter |
|---|---|---|---|
| **SSH** | `ssh cbc-prod` → port 22 (root) | SSH-nøgle (key-only) | Password-auth slået fra. Alias i laptoppens `~/.ssh/config`. |
| **Plesk-panel** | `https://server.cbcit.dk:8443` | Plesk-login **bag Cloudflare Access** | Port 8443 er **ikke** firewall-åben — kun via CF Tunnel. |
| **WP-admin (event)** | `https://event.cbcit.dk/wp-admin/` | WP-login (+ magic-link for deltagere) | Bag Cloudflare. `FORCE_SSL_ADMIN=true`. |
| **WP-admin (datagaarden)** | `https://datagaarden.dk/wp-admin/` | WP-login | Bag Kents LB. Wordfence aktiv. |
| **Cloudflare-dashboard** | `dash.cloudflare.com` (konto CBC IT v2) | CF-login (2FA) | DNS/WAF/Access/Tunnel-styring. |
| **Hetzner-konsol** | `console.hetzner.cloud` | Hetzner-login (2FA) | Power-cycle, snapshots. |

**Alle logins → break-glass (07).** MFA: Plesk har MFA-extension installeret;
Cloudflare + Hetzner har 2FA (verificér at det er aktivt — 07 dækker recovery-koder).

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

- **Laptop-adgang:** `ssh cbc-prod` bruger nøgle `cbc_hetzner` (ed25519, ingen
  passphrase — bevidst, for non-interaktive deploy-scripts) via `~/.ssh/config`.
  Nøglen skal beskyttes; genskabelse ved laptop-tab → se 07 + plugin-docs §14.
- **Brute-force:** fail2ban-jail `ssh` er aktiv (se §5).

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
ip  saddr @cf4 tcp dport { 80, 443 } accept  # web kun fra Cloudflare (v4)
ip6 saddr @cf6 tcp dport { 80, 443 } accept  # web kun fra Cloudflare (v6)
ip  saddr { 185.21.232.10, .11, .12 } tcp dport 443 accept  # KENTS-LB-TEMP
```

- `@cf4`/`@cf6` = **alle Cloudflare IP-ranges** (named sets). Web-origin er dermed
  låst til Cloudflare — ingen kan ramme 80/443 direkte udenom CF.
- **`KENTS-LB-TEMP`** = de tre Kent-LB-IP'er, åbnet på 443 for `datagaarden.dk`.
  Markeret midlertidig; `counter 0` pr. 2026-07-20 (ingen trafik endnu — WIP).
- **8443 (Plesk) er bevidst IKKE i input** → panelet kan kun nås via CF Tunnel.

### 3.2 Output-chain (policy DROP — egress-hærdning)

Kun disse udgående forbindelser tillades; alt andet logges + droppes:

```
lo, established/related, icmp
udp 53 / tcp 53   (DNS)
udp 123           (NTP)
udp 67            (DHCP)
tcp 80, 443, 587  (web-opdateringer + Brevo SMTP-submission)
udp/tcp 7844      (Cloudflare Tunnel til CF's edge)
→ resten: rate-limited log "cbc_fw egress-drop:" + drop
```

> **Konsekvens for drift:** vil du tilføje en ny udgående integration (fx en API
> på en anden port), **skal** du tilføje en egress-accept-regel i `cbc_fw`, ellers
> fejler forbindelsen stille. Tjek `journalctl -k | grep cbc_fw` for egress-drops.

### 3.3 Hvor reglerne bor + ekstra firewall-lag

- `nft list table inet cbc_fw` viser den kørende tabel; regel-filen er
  **`/etc/nftables.d/cbc_fw.nft`** (+ `.fallback`) — jf. break-glass 07 §5.
- **Dead-man switch-disciplin:** enhver firewall-ændring køres med en
  `systemd-run --on-active=300 … nft delete table inet cbc_fw`-sikring FØR apply
  (test frisk SSH, annullér derefter) — se 07 §9.
- **Hetzner Cloud Firewall `cbc-edge`** (id 11085732) ligger som ekstra lag FORAN
  boksen (styres i Hetzner-konsollen, påvirker ikke noVNC). Regler: ‹verificér i
  Hetzner-konsollen — forventeligt spejl af cbc_fw-input›.

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
| Connector | kører på `server.cbcit.dk` (IPv6-udgående), cloudflared 2026.7.1, datacenter `fra`, status Healthy |
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

### 4.2 Cloudflare WAF (verificeret i dashboard 2026-07-20)

| Lag | Konfiguration |
|---|---|
| **Managed rules** | Cloudflare Managed Ruleset: **aktiv** · OWASP Core Ruleset: *deaktiveret* (bevidst) |
| **Super Bot Fight Mode** | Aktiv (Pro-plan) — én custom skip-regel: "Exempt api + legacy from Super Bot Fight Mode" (hostname `api.cbcit.dk`/`legacy.cbcit.dk`, ikke-browser API-klienter) |
| **Rate limiting** | 1 regel: "Auth endpoint rate limit" — URI path starts with `/auth/` → **Managed Challenge** (aktiv) |

> Bemærk: rate-limit-reglen rammer `/auth/` — event-sitets login-flade er `/login/`
> (+ `admin-post.php`-endpoints). Plugin'et har sin egen app-niveau rate-limiting
> (login-lofter + venue-IP-allowlist), så CF-reglen er formentlig rettet mod
> api-backenden. Verificér intentionen ved lejlighed.

---

## 5. Netværks-/host-sikkerhed på boksen

| Lag | Status (2026-07-20) |
|---|---|
| **fail2ban** | Aktiv — 13 jails: `ssh`, `recidive`, `plesk-apache`, `plesk-apache-badbot`, `plesk-wordpress`, `plesk-postfix`, `plesk-dovecot`, `plesk-proftpd`, `plesk-panel`, `plesk-roundcube`, `plesk-modsecurity`, `plesk-one-week-ban`, `plesk-permanent-ban` |
| **Imunify** | Installeret (Plesk-extension `imunify360` + `imunify-antivirus`/`-core`/`-notifier` cron). Malware-scanning. |
| **ModSecurity** | Aktiv (nginx `modsecurity_nginx.conf` + fail2ban-jail `plesk-modsecurity`) |
| **Cloudflare WAF** | ‹CF-DASHBOARD — UDFYLD: managed ruleset(s), custom rules, evt. rate-limiting-regler (P2-listen)› |
| **Wordfence** | Aktiv på `datagaarden.dk` (app-niveau WAF; `wordfence-waf.php`) |

---

## 6. Origin-bypass-værn (`cbc-origin-guard.conf`)

Fil: `/etc/nginx/conf.d/cbc-origin-guard.conf` (oprettet 2026-07-20 i forbindelse
med datagaarden-LB-sporet).

- **Problem det løser:** når firewallen åbnes for Kents LB på 443, kan LB-IP'erne
  teknisk sende *enhver* Host-header til origin — også `Host: event.cbcit.dk`.
  Firewallen kan ikke filtrere på Host.
- **Mekanik:** en nginx `geo`-blok på `$realip_remote_addr` (den **rå** TCP-peer,
  upåvirket af `set_real_ip_from`) sætter `$cbc_origin_not_trusted = 1` for enhver
  peer der **ikke** er Cloudflare, loopback eller egen origin-IP.
- **Håndhæves** i `event.cbcit.dk` + `cbcit.dk` via deres nginx additional
  directives: `if ($cbc_origin_not_trusted) { return 403; }`.
- **`datagaarden.dk` er bevidst undtaget** (har ingen additional directives) — den
  skal netop kunne nås af Kents LB.

> **Rør ikke** ved geo-listen uden at opdatere den mod Cloudflares aktuelle
> IP-ranges (samme liste som cbc_fw's `@cf4/@cf6`).

---

## 7. Applikations-hærdning (event.cbcit.dk)

### 7.1 wp-config.php (verificeret 2026-07-20)

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

**Verbatim kilde** (dump af `/var/www/vhosts/system/event.cbcit.dk/conf/vhost_nginx.conf`,
2026-07-21 — det Plesk genererer af "Additional nginx directives"). Ved migrering
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
```

> **Vedligehold:** ændres direktiverne i Plesk, opdatér dumpet her i samme
> ombæring. Verificér effekten udefra med `tools/web-exposure-check.sh` (se §8).

### 7.3 `.git`-eksponering (S1) — verificeret lukket

`.git/` i plugin-mappen returnerer **403** udefra (testet via CF 2026-07-20).
Blokeres på origin-niveau via Plesk's genererede nginx-config (dot-fil-deny) +
Cloudflare. Defense-in-depth: selv uden reglen kan origin ikke nås direkte
(firewall + origin-guard).

### 7.4 Fil-permissions

- Web-filer: dirs `755`, filer `644` (deploy-scripts normaliserer dette — kritisk
  pga. en umask-lærdom, se 06-runbooks §gotchas).
- `wp-config.php`: `600`. Backup-mappe `/var/backups/cbc-pre-deploy`: `700`.

---

## 8. Verifikations-kommandoer

```bash
ssh cbc-prod 'sshd -T | grep -E "permitroot|passwordauth|pubkey"'
ssh cbc-prod 'nft list table inet cbc_fw'
ssh cbc-prod 'systemctl is-active cloudflared fail2ban; fail2ban-client status'
ssh cbc-prod 'cat /etc/nginx/conf.d/cbc-origin-guard.conf'
ssh cbc-prod 'curl -sI -A Mozilla https://event.cbcit.dk/wp-content/plugins/cbc-event-planner/.git/config | head -1'  # → 403
bash drift/tools/web-exposure-check.sh   # ekstern S2-verifikation: docs/ m.m. blokeret, site OK (exit 0 = alt grønt)
```
