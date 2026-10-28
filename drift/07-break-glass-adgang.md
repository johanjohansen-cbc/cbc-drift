# 07 — Break-Glass: Adgang til CBC-produktionsserveren hvis den driftsansvarlige falder bort

**Status:** Successions-/katastrofe-dokument ("bus factor"). Oprettet 2026-06-15 · Revideret 2026-07-20 (post-prod-dag) · 2026-08-27 (datagaarden → CF for SaaS) · **Opdateret 2026-10-27** (efter okt. 2026: PHP-0-day, card-testing-hardening, blast-radius-værn, patch-automatik og fuld sikkerhedsscanning 26/10 — verificeret mod live server, ekstern scan og Cloudflare-API).  
**Formål:** Sætte en betroet CBC IT-kollega i stand til at **genvinde fuld kontrol** over hele drifts-stakken på serveren `server.cbcit.dk` — primært [https://event.cbcit.dk](https://event.cbcit.dk) (CBC Event Planner), men boksen hoster også **cbcit.dk (WooCommerce-webshop m. QuickPay-betalinger)** og **datagaarden.dk**. Dokumentet forklarer HVOR adgang og hemmeligheder ligger, og HVORDAN man bruger dem. Det indeholder **ingen hemmeligheder selv** (pointer-only by design).  
**Målgruppe:** En teknisk CBC IT-medarbejder med terminal-kendskab. Forudsætter IKKE forudgående kendskab til projektet.

> 📘 **Teknisk driftsmanual:** Den fulde, standardiserede driftsdokumentation
> (arkitektur, firewall, deploy, backup, runbooks) ligger i **`_handover/drift/`
> (00–06)** — dette dokument er ADGANGS-nøglen; driftsmanualen er HÅNDBOGEN.
> Læs dem sammen.

> ⚠️ **Dette dokument er fortroligt, men ikke hemmeligt.** Det kan opbevares i det private repo og i CBC's interne dokumentation. De faktiske nøgler/passwords ligger ét sted: **den delte CBC password manager** (se §2). Mister man adgang DERTIL, brug fysisk/organisatorisk break-glass i §11\. 

---

## 0\. TL;DR — Start her (rækkefølgen er bevidst)

Hvis du lige er trådt ind og skal overtage driften, gør dette i rækkefølge:

1. **Skaf adgang til den delte CBC password manager** (§2). Den er _linchpin_ — alt andet hænger på den. Produktet er **Roboform**; hvert systems adgang ligger som **safe note eller gemt login under servicens navn** (fx "Hetzner", "Cloudflare", "Brevo", "QuickPay", "Simply"). Din leder/IT-ansvarlig (§11: AH/JNP) kan tildele dig adgang.
2. **Genskab SSH-adgang til serveren** (§4): hent den private nøgle `cbc_hetzner` fra vault'et, installér den, log ind med `ssh root@178.104.70.94`.
3. **Læs creds-filen på serveren** (§5): `cat /root/cbc-deploy-creds.txt` — her står DB-, WP-admin- og root-OS-password samlet.
4. **Verificér de eksterne konti** (§6): Hetzner Cloud, Cloudflare, Brevo, GitHub, Microsoft 365/OneDrive, domæne-registrar. Sørg for at CBC (ikke kun Johans personlige konti) ejer dem.
5. **Læs §9 (må ALDRIG ændres)** før du rører noget. Et par foot-guns kan vælte både dette site og ~18 andre CBC-sites.

Resten af dokumentet uddyber hvert trin + recovery-scenarier.

---

## 1\. Hele billedet — hvad kører hvor

CBC Event Planner er et WordPress-baseret tilmeldings-/konferencesystem til CBC's årlige KickOff-event. Det består af:



| Lag | Hvad | Hvor det lever |
| --- | --- | --- |
| Domæne | event.cbcit.dk (subdomæne under cbcit.dk) | DNS hos Cloudflare, konto **"CBC IT v2"**; cbcit.dk registreret hos **Simply.com** (rettet 2026-07-20 — tidligere fejlagtigt angivet som punktum.dk) |
| Server | Hetzner Cloud CPX32 (4 vCPU / 8 GB), Ubuntu 24.04 | Hetzner Cloud, IP 178.104.70.94, navn cbc-server (id 135078172) |
| Web-panel | Plesk Obsidian 18.0.81.x (auto-opdateres) | På serveren, port 8443. **Primær adgang: `https://plesk-event.cbcit.dk`** (Cloudflare Access → tunnel `cbc-plesk` → localhost:8443; verificeret 2026-10-27). Fallback: SSH-tunnel (`ssh -L 8443:127.0.0.1:8443 cbc-prod` → `https://localhost:8443`). Port 8443 er IKKE åben i firewallen udefra. |
| Web-stack | nginx → Apache → PHP-FPM (plesk-php84, 8.4.27) | På serveren |
| Sites på boksen | **event.cbcit.dk** (WP 7.1.3, plugin cbc-event-planner 2.7.0 + tema cbc-child) · **cbcit.dk** (WP 7.1.3 + **WooCommerce-webshop m. QuickPay-betalingsgateway**) · **datagaarden.dk** (WP 7.1.3, bag Cloudflare for SaaS siden 2026-08-26 — DNS hos wwi, custom hostnames i cbcit.dk-zonen). Versions-frysen fra før konferencen er ophævet 2026-10-08. | /var/www/vhosts/<domæne>/httpdocs |
| Kode-leverance | Self-hosted bare git repo + privat GitHub-mirror | Server /var/git/*.git + GitHub johanjohansen-cbc |
| Udgående mail | Postfix (kun loopback) → Brevo SMTP-relay (port 587) | Brevo Free-plan; SASL-creds på serveren |
| Backup | Plesk Backup Manager → Microsoft OneDrive (M365), password-krypteret · Hetzner-snapshot ugentligt fra Johans PC | OneDrive retention 7 dage · Hetzner (3 ugentlige) |
| Edge/sikkerhed | Cloudflare (proxied + WAF + Managed-Challenge-regler + Access) + Hetzner Cloud Firewall `cbc-edge` (id 11085732) + host-nftables `cbc_fw` (ind + udgående allowlist for web-processer) + origin-guard + ModSecurity/Imunify/fail2ban/Wordfence | Cloudflare + Hetzner + serveren |
| Patch-automatik | `cbc-security-updates.sh` hver 4. time (OS-security, Plesk-PHP, cloudflared, Imunify) + Plesk-natkørsel + advisory-watch (daglig varsling, ugentlig "alt OK"-mail) | Serveren (cron) — se driftsmanual 04 §2.3 |



**Vigtigt:** Der findes **ingen staging-server** — der deployes direkte til prod via git (med backup + verifikation). Local by Flywheel på Johans maskine er dev-sandkassen. **datagaarden.dk** når serveren via Cloudflare for SaaS (siden 2026-08-26; Kents-LB-broen og `KENTS-LB-TEMP`-firewall-reglen er nedlagt 2026-08-27, se §6.8).

---

## 2\. Linchpin: Den delte CBC password manager

**Alt afhænger af dette ene punkt.** Den delte CBC password manager (Roboform — entries ligger som safe notes/gemte logins under servicens navn) indeholder følgende. **Alle 11 punkter verificeret til stede af Johan 2026-07-20:**

* [ ] **SSH privat nøgle `cbc_hetzner`** (ed25519) + tilhørende public key + `~/.ssh/config`-blok. Fingerprint: `SHA256:JwmGiMeNt/jvjbR04ZrF40qPZo0xCHj0etjtJnv5Quc`.
* [ ] **SSH privat nøgle `cbc_github`** (ed25519, til GitHub-mirror push).
* [ ] **Hetzner Cloud-konto-login** (eller hvem der er konto-ejer) + 2FA-recovery.
* [ ] **Cloudflare-konto-login — konto "CBC IT v2"** (zonen `cbcit.dk` + Zero Trust/Access) + 2FA-recovery. ⚠️ Der har eksisteret en ældre CBC-Cloudflare-konto — sørg for at vault-entry'en peger på **CBC IT v2** (oprettet ved prod-dagen 2026-07-10).
* [ ] **Cloudflare Tunnel connector-token** (tunnel `cbc-plesk`) — bruges hvis cloudflared-servicen skal geninstalleres på (ny) server. Kan altid re-udstedes fra CF Zero Trust → Networks → Tunnels.
* [ ] **Brevo-konto-login** + SMTP-nøgle (brugernavn `ad4773001@smtp-brevo.com`).
* [ ] **Microsoft 365 / OneDrive-konto** der huser Plesk-backups + **Plesk backup-krypteringspassword** ("Specified password" — KRÆVES for restore på frisk server).
* [ ] **GitHub-konto** `johanjohansen-cbc` (login/2FA-recovery).
* [ ] **QuickPay-konto** (betalingsgateway for webshoppen på cbcit.dk — penge-kritisk!).
* [ ] **Simply.com-login** (registrar for cbcit.dk + datagaarden.dk).
* [ ] **WP-admin + Plesk-admin + root-OS-password** — disse står OGSÅ i `/root/cbc-deploy-creds.txt` på serveren, men bør spejles i vault'et som break-glass.

**Tilføjet 2026-10-27 — findes i dag KUN på Johans PC eller serveren, bør spejles/afklares i vault'et:**

* [ ] **Hetzner API-token til snapshot-rutinen** — DPAPI-krypteret i `C:\Users\JohanJohansen\cbc-ops\hetzner-token.xml` (kan kun læses af Johans Windows-login). Ved overdragelse: lav nyt Read&Write-token i Hetzner-konsollen og sæt rutinen op på efterfølgerens maskine (05 §1). Uden den stopper de ugentlige snapshots tavst — kun mandagsmailens udebliven afslører det.
* [ ] **Cloudflare API-token** (`CF_API_TOKEN`, bruger-miljøvariabel på Johans PC; Zone WAF Edit, Cache Rules Edit, Zone Settings/Analytics Read for zonen cbcit.dk, ingen udløb). Bruges til WAF-regler via API. Kan re-udstedes i CF-dashboardet → My Profile → API Tokens.
* [ ] **Datagaardens SFTP-password** (Linux-bruger `datagaardendk`, kun fra 87.55.238.154) — Datagaardens egne folk har det. Mistes det: `passwd datagaardendk` som root og giv dem det nye.
* [ ] **Partner-creds** `/root/cbc-partner-sites-creds.txt` (600, 2026-07-17) på serveren — logins til partner-sites brugt ved migreringerne. Læs før de slettes.

**Hvordan får en efterfølger adgang til vault'et?**  
Alle har adgang via safe notes i Roboform.

---

## 3\. Adgangs-topologien (hvem/hvad kan komme ind)

For at undgå misforståelser:

* **Der findes ingen separat "Claude"-adgang.** Al automatisering (Claude Code-værktøjet) kører gennem Johans maskine med Johans nøgle. Forsvinder Johans maskine, forsvinder den vej — men serveren er uberørt og tilgås med nøglen fra vault'et.
* **Serverens `/root/.ssh/authorized_keys` indeholder KUN nøglen `cbc_hetzner`.** Det er den eneste SSH-vej ind **som root**.
* **To SFTP-only-brugere findes desuden på port 22** (chroot, ingen shell, ingen forwarding — driftsmanual 02 §2.1): `kent` (partner-dropbox, nøgle-only, udløber 2027-01-01 → slet) og `datagaardendk` (Datagaardens egen fil-upload til deres docroot, **password, men kun fra deres kontor-IP 87.55.238.154**). Ingen af dem kan eskalere til root.
* **Password-login over SSH er slået FRA for alle andre** (`PasswordAuthentication no`). Root-OS-passwordet virker derfor KUN på Hetzners web-konsol (noVNC) — som er den ultimative out-of-band redning hvis nøglen tabes (§8).
* **Nøglen har bevidst INGEN passphrase** (så automatisering kører non-interaktivt). Recovery-nettet (root-password + noVNC) dækker risikoen ved tab.

---

## 4\. Trin-for-trin: Genskab SSH-adgang

På en frisk Windows- eller Linux-maskine:

1. Hent `cbc_hetzner` (privat nøgle) fra password manageren (§2). Gem som `~/.ssh/cbc_hetzner` (Linux/macOS) eller `C:\Users\‹dig›\.ssh\cbc_hetzner` (Windows).
2. **Lås filrettigheder** — OpenSSH afviser en nøgle med for åbne rettigheder:
  * Linux/macOS: `chmod 600 ~/.ssh/cbc_hetzner`
  * Windows (PowerShell): `icacls "$env:USERPROFILE\.ssh\cbc_hetzner" /inheritance:r /grant:r "$($env:USERNAME):(R)"`
3. Tilføj en `~/.ssh/config`-blok (genskab fra vault'et, eller skriv):
    
    `Host cbc-prod  
    HostName 178.104.70.94  
    User root  
    IdentityFile ~/.ssh/cbc_hetzner  
    IdentitiesOnly yes  
    `

  
⚠️ **Gem `config` UDEN UTF-8 BOM** — en BOM giver OpenSSH-fejlen "Bad configuration option".
4. Log ind: `ssh cbc-prod` (eller `ssh -i ~/.ssh/cbc_hetzner root@178.104.70.94`).
5. Hvis det virker: du er root på serveren. Gå til §5\.
6. Hvis nøglen er tabt/ugyldig: gå til §8 (noVNC-konsol-redning).

---

## 5\. På serveren: hvor alt står

Når du er logget ind som root: 
    
    `cat /root/cbc-deploy-creds.txt        # DB-navn/-bruger/-pass, tabel-prefix,  
    # WP-admin-bruger/-pass/-email, root_os_password  
    `

Den fil (chmod 600) er den centrale operative creds-samling på serveren.

**Køre ting som WordPress-sysbruger** (web-filer ejes af denne, ikke root): 
    
    `su -s /bin/bash event.cbcit.dk_x3pjx5okzbn -c "<kommando>"  
    `

**WP-CLI** (bemærk det påkrævede memory-flag): 
    
    `su -s /bin/bash event.cbcit.dk_x3pjx5okzbn -c \  
    "/opt/plesk/php/8.4/bin/php -d memory_limit=512M /usr/local/bin/wp \  
    --path=/var/www/vhosts/event.cbcit.dk/httpdocs <args>"  
    `

**Plesk-panel-login** (hvis password ukendt): `plesk login admin` minter et engangs-login-link. Admin-brugernavnet er altid `admin` (ikke en email).

**Database direkte:** 
    
    `MYSQL_PWD=$(cat /etc/psa/.psa.shadow) mysql -uadmin  
    `

Tabel-prefix: `wp866a4c_`.

**Vigtige stier på serveren:**



| Hvad | Sti |
| --- | --- |
| WordPress docroot | /var/www/vhosts/event.cbcit.dk/httpdocs |
| Operative creds | /root/cbc-deploy-creds.txt |
| Bare git repos (deploy-kilde) | /var/git/cbc-event-planner.git + /var/git/cbc-child.git |
| Deploy-scripts | <plugindir>/deploy.sh + <temadir>/deploy-theme.sh |
| Pre-deploy backups | /var/backups/cbc-pre-deploy (retention 7) |
| Host-firewall regler | /etc/nftables.d/cbc_fw.nft (+ cbc_web_egress_elements.nft, daterede .pre-*-backups, .fallback) · allowlists /etc/cbc-web-egress-hosts.txt + -ranges.txt |
| Brevo SMTP-creds | /etc/postfix/sasl_passwd (600, postmap'd) |
| Hærdnings-drop-ins | /etc/ssh/sshd_config.d/99-cbc-hardening.conf (+ Match-blokke nederst i /etc/ssh/sshd_config), /etc/sysctl.d/99-cbc-hardening.conf, /opt/plesk/php/8.4/etc/php.d/zz-cbc-upload-progress.ini |
| **Hærdnings-runbook okt. 2026** | **/root/cbc-hardening-2026-10/README.md** — alle ændringer siden 22/10 med rollback pr. punkt; `stage/` = kopier af scripts, `perms-rollback/`, `rollback-step*.sh` |
| CBC-scripts (cron/timers) | /usr/local/sbin/cbc-*.sh · /etc/cron.d/cbc-* · /etc/systemd/system/cbc-*.timer · logs /var/log/cbc-*.log |
| Must-use-plugins (uden for git) | /var/www/vhosts/cbcit.dk/httpdocs/wp-content/mu-plugins/cbc-checkout-guard.php · /var/www/vhosts/event.cbcit.dk/httpdocs/wp-content/mu-plugins/cbc-no-user-enum.php |
| Partner-creds | /root/cbc-partner-sites-creds.txt (600) |
| SFTP-chroots | /srv/partner-dump (kent) · /srv/dg-sftp (datagaardendk → datagaarden-docroot) · /etc/ssh/authorized_keys.d/kent |
| Øvrige sites' docroots | /var/www/vhosts/cbcit.dk/httpdocs (sysuser `cbcitdk`, DB `cbcit_prod`, prefix `wp_`) · /var/www/vhosts/datagaarden.dk/httpdocs (sysuser `datagaardendk`, DB `datagaarden_prod`, prefix `wp_`) — DB-passwords i deres wp-config.php (600) |



---

## 6\. De eksterne konti — verificér ejerskab

Serveren kan genskabes; men disse eksterne tjenester er kritiske og skal kontrolleres af CBC, ikke af en privatperson. Tjek hver:

### 6.1 Hetzner Cloud (serveren selv)

* Konsol: [https://console.hetzner.cloud](https://console.hetzner.cloud) — projekt indeholder server `cbc-server` (id `135078172`) + firewall `cbc-edge` (id `11085732`).
* **noVNC-konsol** herfra er den ultimative redning (§8).
* API-tokens: lav ad hoc Read&Write-token ved behov, **slet den bagefter**. Eneste permanente token er snapshot-rutinens (DPAPI-krypteret på Johans PC, §2) — den skal re-udstedes ved overdragelse.
* **Snapshots:** `cbc-weekly-<dato>` tages automatisk hver mandag 09:00 fra Johans PC (3 beholdes); manuelle snapshots (andet navn) prunes aldrig. Tjek i konsollen under Snapshots at det nyeste er under en uge gammelt.

### 6.2 Cloudflare (DNS + edge-proxy + Access) — konto **"CBC IT v2"**

* Zonen `cbcit.dk` (Pro-plan, 59 records). `event.cbcit.dk` + `cbcit.dk` er **proxied** A-records (`178.104.70.94`, orange sky).
* ⚠️ **Zone-SSL-mode = "Full" og er DELT med ~18 andre CBC-sites på `185.21.232.10`. MÅ ALDRIG ændres** (se §9).
* **Zero Trust/Access:** app "CBC Plesk Panel" → `plesk-event.cbcit.dk` → tunnel `cbc-plesk` → serverens localhost:8443. Policy "Allow cbcit.dk", session 24 t, team `fancy-sound-8625.cloudflareaccess.com`. Det er den PRIMÆRE Plesk-adgang.
* **WAF:** Cloudflare Managed Ruleset + OWASP aktiv + Super Bot Fight Mode. **To CBC-custom-regler (Managed Challenge):** på WooCommerce-checkout for `cbcit.dk` (card-testing-værn 2026-10-21) og på `/wp-login.php` for `event.cbcit.dk` (2026-10-26). Begge rate-limit-slots er optaget af api-backenden. Reglerne er host-scopede — zonen deles med ~18 andre sites, så lav aldrig zone-wide regler. Detaljer: driftsmanual 02 §4.2.
* Brevo-relateret DNS (DKIM `brevo1/brevo2._domainkey`, `brevo-code`, DMARC) ligger også her. **@cbcit.dk-indgående mail = Microsoft 365** (MX → `mail.protection.outlook.com`).
* Origin-certs (CF-signerede, på serveren): udløb 2041 — ingen Let's Encrypt-fornyelse at bekymre sig om for de CF-frontede sites.
* Fuld CF-dokumentation: driftsmanualen `_handover/drift/01` §4 + `02` §4.

### 6.3 Brevo (udgående mail-relay)

* Free-plan, 300 mails/dag. SMTP-login `ad4773001@smtp-brevo.com` (nøgle i vault + på server).
* Leverings-problemer fejlsøges i **Brevo dashboard → Transactional → Logs + Suppression lists** (Brevo dropper tavst blokliste-adresser).

### 6.4 GitHub (off-site kode-backup)

* Konto `johanjohansen-cbc`, **private** repos `cbc-event-planner` + `cbc-child`.
* ⚠️ Dette er en **personlig** GitHub-konto. **Anbefaling:** overfør repos til en CBC-organisation, eller tilføj mindst én anden CBC-ejer, så koden ikke låses inde ved Johans bortfald.

### 6.5 Microsoft 365 / OneDrive (backups)

* Plesk Backup Manager skubber daglige fulde/inkrementelle backups hertil (retention 7).
* **Plesk backup-krypteringspassword** (i vault) KRÆVES for at restore på en frisk server.
* Adgang afhænger af M365-konto + MFA — sørg for CBC-administreret konto.

### 6.6 Domæne-registrar (`cbcit.dk` + `datagaarden.dk`)

* **Simply.com** (verificeret af Johan 2026-07-20; dokumentet angav tidligere
  fejlagtigt punktum.dk). Konto-login: vault (§2). SPF-historik i CF-DNS
  (`include:spf.simply.com`) stemmer med Simply som leverandør.

### 6.7 QuickPay (webshop-betalinger — cbcit.dk)

* Webshoppen på cbcit.dk kører WooCommerce med **QuickPay-betalingsgateway**
  (plugin `woocommerce-quickpay`). Konto-login + API-nøgler: vault (§2).
* Penge-kritisk. Aftale-ejerskab: **CBC IT ejer både QuickPay-kontoen og
  indløseraftalen** (bekræftet 2026-07-20) — ingen personafhængighed her.

### 6.8 Kent / ekstern load balancer (datagaarden.dk) — HISTORISK siden 2026-08-27

* **Løst før tid:** `datagaarden.dk` blev DNS-flippet til **Cloudflare for SaaS**
  2026-08-26 (DNS hos wwi: www-CNAME + apex-ANAME → `sites.cbcit.dk`; custom
  hostnames + certifikater i cbcit.dk-zonens "SSL for SaaS"). 2026-08-27 blev
  Kents-LB-broen ryddet op: `KENTS-LB-TEMP`-firewall-reglen fjernet, LB-IP'erne
  ud af fail2ban, vhost skiftet til CF-real-ip + origin-guard.
* Kobalt-aftalens ophør 2026-12-31 har derfor **ingen konsekvens** for denne boks.
  Kent-kontakt (fortsat relevant for andre cbcit.dk-subdomæner på 185.21.232.x
  uden for boksen): **Kent Grady — kgrady@kobalt.dk** (Kobalt er også
  CF-org-admin-kontakten i §11 og forklarer `spf1.kobalt.dk` i SPF-historikken).

---

## 7\. Daglig drift — hvor runbooks ligger

Den løbende drift er dokumenteret to steder:

* **`drift/00–06` i dette repo** — den samlede tekniske driftsmanual for HELE
  serveren (arkitektur, firewall, CF-lag, alle tre sites, backup, runbooks,
  gotchas). Verificeret mod live server + Cloudflare 2026-07-20, re-verificeret
  2026-10-26/27. **Start dér.** Kanonisk hjem: privat GitHub-repo
  **`johanjohansen-cbc/cbc-drift`** (dette dokument ligger samme sted —
  arbejdskopi i `C:\Users\JohanJohansen\Local Sites\cbc-event-planner\app\public\_handover\drift\`
  på Johans PC).
* **`/root/cbc-hardening-2026-10/README.md` på serveren** — den operative
  ændringslog for al hærdning siden 22/10-2026 (egress-filter, PHP
  `disable_functions`, nginx-grænser, patch-cron, advisory-watch, audit-rettelser)
  med rollback-kommando pr. punkt. Læs den, før du ændrer firewall, PHP eller nginx.
* Plugin-repoets `docs/`-mappe — applikations-/deploy-nære dokumenter:

* **`docs/05-deploy-workflow.md`** — komplet deploy-procedure. Kort: lokalt `git push both main` (skubber til både bare repo OG GitHub-mirror), derefter på serveren som root `bash <plugindir>/deploy.sh` (laver backup → pull → chown → db-migrate → php-fpm reload → verifikation). Tema deployes FØR plugin.
* **`docs/06-security-pre-deploy.md`** — sikkerheds-tjekliste før deploy.
* **Mail-fejlfinding** (fra drifts-noter): `journalctl --since "-20min" | grep -E "postfix|plesk-sendmail"` → nåede mailen postfix med `status=sent`? Så er vores side færdig, resten er Brevo-nedstrøms.
* **Login rate-limit nulstilling:** transients `cbc_login_rl_*` / `cbc_ml_rl_*` (per IP/email). `wp option list` skjuler transients — find dem via SQL i `wp866a4c_options`.

**Deploy-foot-gun (vigtig):** `deploy.sh` kører kun DB-migration når schema-VERSIONEN ændres. Ved en ren PHP-fase med data-only-migration (fx mail-skabelon-seeds) skal du køre `wp cbc db migrate` **manuelt** bagefter (den er idempotent).

---

## 8\. Recovery-scenarier

### 8.1 SSH-nøglen er tabt, men serveren kører

1. Log ind på **Hetzner Cloud Console** (§6.1) med CBC's konto.
2. Åbn **noVNC-konsollen** for `cbc-server`.
3. Log ind som `root` med **root-OS-password** (fra creds-filen/vault).
4. Generér en ny SSH-nøgle lokalt, og tilføj dens public-del til `/root/.ssh/authorized_keys`.
5. Test ny nøgle via SSH, opdatér vault'et.

> noVNC virker ALTID — også ved totalt nøgletab — fordi password-login kun er lukket over SSH, ikke på konsollen. Hetzner Cloud Firewall påvirker ikke noVNC (out-of-band). 

### 8.2 Serveren er væk/korrupt — restore på frisk server

0. **Hurtigste vej, hvis Hetzner-kontoen lever:** gendan seneste `cbc-weekly-*`-snapshot i Hetzner-konsollen (hele disken inkl. al server-config). RTO 15–30 min, RPO op til 7 dage. Resten af punkterne gælder, når snapshottet ikke kan bruges.
1. Provisionér ny Hetzner CPX32 + Plesk Obsidian + PHP 8.4\.
2. Hent seneste backup fra **OneDrive** via Plesk Backup Manager (kræver backup-krypteringspasswordet fra vault; manuel download fra OneDrive-webben er ubrugelig — formatet er chunket).
3. Gendan subscriptions (filer + DB + wp-config + sysuser-crontabs + mu-plugins følger med). **Server-level config følger IKKE med og skal genskabes:** `cbc-origin-guard.conf` (ellers fejler nginx), host-firewall `cbc_fw.nft` + egress-allowlists, alle `cbc-*`-scripts/cron/timers, sshd-drop-in + SFTP-Match-blokke, Postfix `loopback-only` + Brevo `sasl_passwd`, PHP-drop-in, Imunify-skema. Den fulde liste og rækkefølge står i **driftsmanual 05 §2.3** (gennemprøvet ved restore-drill 2026-08-18).
4. Peg Cloudflare A-records (`event`, `cbcit.dk`, `sites`) mod ny IP; opdatér origin-IP'en i `cbc-origin-guard.conf` og Hetzner Cloud Firewall; genudsted CF-tunnel-connector (§2).
5. **Restore-drill er gennemført 2026-08-18** (event-subscriptionen gendannet på scratch-server; målt RTO ~45–60 min med proceduren). Resultat + fund: driftsmanual 05 §3.1. Gentag efter større infra-ændringer — den okt. 2026-hærdning er ikke drillet endnu.

### 8.3 Kun koden skal genskabes

Koden findes tre steder: serverens bare repo (`/var/git/`), GitHub-mirror (`johanjohansen-cbc`), og Johans Local-maskine. Klon fra GitHub hvis serveren er væk.

---

## 9\. Må ALDRIG ændres (foot-guns)

Disse kan vælte prod — og nogle rammer langt bredere end dette ene site:

1. **Cloudflare zone-wide SSL-mode** (pt. "Full"). Den er **DELT med ~18 andre CBC-live-sites** på samme origin-IP (`185.21.232.10`). Ændrer du den, kan du tage alle de andre sites ned. Rør den aldrig.
2. **fail2bans nftables-tabel** (`table ip filter`). Host-firewallen bruger en SEPARAT tabel (`table inet cbc_fw`) netop for ikke at kollidere. Kør ALDRIG `nft flush ruleset`.
3. **Postfix `inet_interfaces`** — skal være `loopback-only`. Plesk kan nulstille den til `all` ved `plesk repair mail`; tjek `postconf -h inet_interfaces` hvis mail-porte pludselig er åbne.
4. **Egress-firewall (to lag)** — udgående trafik er default-drop, og **WordPress-processerne må kun nå allowlistede hostnavne** (`/etc/cbc-web-egress-hosts.txt`, enforce siden 2026-10-23). Et nyt plugin/API/licens-server bliver tavst droppet, til hostnavnet er tilføjet + `cbc-web-egress-refresh.sh` kørt (driftsmanual 06 §1.9). Nødbremse: `cbc-web-egress-mode.sh log-only`. Ikke-web-processer på skæve porte kræver stadig en regel i `output`-chain.
5. **Firewall-ændringer** — kør ALTID med en "dead-man switch" (`systemd-run --on-active=300 ... nft delete table inet cbc_fw`) FØR du applyer, test frisk SSH, og annullér dead-man først når du er sikker. Ellers kan en regelfejl låse dig ude. Brug `cbc-fw-apply.sh` til at genindlæse — ikke `nft -f` direkte.
6. **WP/PHP-version** — frysen er ophævet (2026-10-08). **WordPress-MAJOR-opgraderinger kun mellem konferencer**, altid med snapshot + DB-dump først og test på Local. PHP bliver på 8.4 (Plesk-repo pinned); 8.5 kun efter test. Sikkerhedspatches kører automatisk.
10. **XML-RPC er lukket** (nginx 403) på alle tre sites, og **brugernavns-enumeration er lukket** på event (mu-plugin). Slå det ikke op igen "fordi et plugin brokker sig" uden at læse driftsmanual 06 §1.13.
11. **Datagaardens SFTP-login er IP-låst** til 87.55.238.154 (sshd Match-blok). Skifter de IP, retter du `Address` — du åbner ikke for alle.
12. **PHP `disable_functions`** (exec/shell_exec/system/proc_open/popen …) er sat pr. domæne i Plesk for alle tre sites. Et plugin der "kræver exec()" får det ikke — find en anden løsning.
13. **Imunify-, integritets- og patch-automatikken sender til `johan@cbcit.dk`.** Sluk ikke jobs, du ikke forstår; de er dokumenteret i `/root/cbc-hardening-2026-10/README.md`.
7. **Nye Plesk-subscriptions SKAL have incoming mail slået fra** (`plesk bin subscription -u <domæne> -mail_service false`) — ellers **kaprer** den nye subscription MX/mail-leveringen for hele `@cbcit.dk` (som ligger på Microsoft 365). Dyrt lært.
8. **Origin-guard** (`/etc/nginx/conf.d/cbc-origin-guard.conf`) — geo-blok der giver 403 til enhver origin-forbindelse der ikke kommer fra Cloudflare/loopback. Håndhæves på ALLE tre sites (datagaarden kom med 2026-08-27 efter CF-flippet). Slet den ikke — og hold geo-listen synkron med CF-real-ip-listerne i vhost'ene.
9. **`sites.cbcit.dk`-recorden + "SSL for SaaS" i cbcit.dk-zonen** — `sites.cbcit.dk` er fallback-origin/CNAME-target for datagaarden.dk's custom hostnames (og evt. fremtidige kundesites). Slettes/afproxies den, dør datagaarden.dk. (`KENTS-LB-TEMP`-reglen fra det gamle LB-spor er fjernet 2026-08-27 og må ikke genindføres.)

---

## 10\. Vedligehold nogen skal huske

* **Det meste passer sig selv:** OS-sikkerhedsopdateringer og Plesk-PHP hver 4. time (`cbc-security-updates.sh`), auto-reboot 04:00 ved kerne-opdatering, Plesk-komponenter natligt, fail2ban, ModSecurity, Imunify (daglig scan 03:00), WP-integritetstjek dagligt, advisory-watch dagligt.
* **WordPress-opdateringer:** på `event.cbcit.dk` er plugin-opdateringer IKKE automatiske (`DISALLOW_FILE_MODS` — deploy via git); WP-core minor patcher sig selv. På `cbcit.dk`/`datagaarden.dk` auto-opdaterer de fleste plugins sig selv. **Majors kun mellem konferencer** (§9.6).
* **ALLE alarm- og statusmails går til `johan@cbcit.dk`:** `cbc-update-notify.php` (event, mandag), `cbc-security-updates.sh`, `cbc-advisory-watch.sh` (mandag "alt OK" + afvigelser), `cbc-egress-report.sh` (dagligt), `cbc-woo-order-watch.sh`, `cbc-wp-integrity.sh`, Imunify `ADMIN_CONTACTS`, Plesk-backup-notifikation, Hetzner-snapshot-mail (fra Johans PC). **→ Ved overdragelse: skift alle til en CBC-fælles drifts-adresse** — listen i driftsmanual 04 §2.3 er komplet. Udebliver mandagsmailerne (advisory "alt OK" + snapshot OK), er noget dødt.
* **Brevo Free = 300 mails/dag.** Ved et større event kan loftet rammes — overvåg.
* **Backups:** verificér jævnligt at OneDrive-backups faktisk skrives (Plesk Backup Manager-log) og at Hetzner-konsollen har et `cbc-weekly-*`-snapshot under en uge gammelt.
* **WP-admin-login på event.cbcit.dk kræver 2FA** (siden 2026-10-28): admins er `cbcadmin` (johan@), `anja@cbcit.dk`, `jan@cbcit.dk` — password + TOTP via `wp-login.php` (bag CF-challenge); magic-link virker ikke for admins. Låst ude → driftsmanual 06 §1.13. Mister ALLE tre adgang: nulstil 2FA-meta via SSH som beskrevet dér.
* **WP-admin-login på cbcit.dk og datagaarden.dk kræver 2FA** (Wordfence Login Security, krav sat 2026-10-28; nådeperiode til 4/11 hhv. 11/11): Wordfence → Login Security → Two-Factor Authentication. Låst ude → driftsmanual 06 §1.13 (WFLS-varianten: `reset_grace_period`).
* **Åbne sikkerhedspunkter pr. 2026-10-28** (fra fuld audit 26/10, prioriteret — fuld liste i Claude-memory `project_prod_security_audit_2026_10_26.md` på Johans PC): 2FA-**enrollment** gennemføres af de enkelte admins inden fristerne (kravet er sat på alle tre sites) · datagaarden-ansatte nedgraderes fra administrator til editor (Datagaardens egen admin) · mail-DNS (SPF-oprydning cbcit.dk, DMARC → quarantine, DMARC + Brevo-DKIM for datagaarden.dk) · deaktivér All-in-One WP Migration på cbcit.dk · CF Origin-cert til datagaarden.dk · fjern TeamViewerQS.exe fra datagaarden.dk/Support · slet `kent`-dropboxen efter 2027-01-01 · ekstern uptime-/dead-man-monitor · OneDrive-backup + snapshot-rutine er personbundne (Johans M365-konto og PC).

---

## 11\. Organisatorisk break-glass (hvis selv vault'et er utilgængeligt)

Hvis ingen kan komme i den delte password manager, er dette sidste udvej:

* **Vault-admin / hvem kan tildele adgang:** AH / JNP
* **Sekundær betroet person med stående adgang:** Ingen
* **Fysisk/forseglet kopi af bootstrap-creds (hvis nogen):** Pengeskab
* **Hetzner konto-ejer + faktureringskontakt:** AH
* **Microsoft 365 global admin (for OneDrive-backup + konti):** AH/JNP
* **Cloudflare org-admin:** Kobalt / JJ
* **Domæne-registrar konto-ejer:** AH

> Uden mindst ét udfyldt punkt her er bus-factor-planen ufuldstændig. Dette er det vigtigste afsnit at få på plads. 

---

## 12\. Verifikations-drill — bevis at adgang virker

Gennemfør denne checkliste mens Johan stadig er tilgængelig (så huller kan lukkes), og igen hvis der sker en overdragelse:

* [ ] Jeg (efterfølger) kan selvstændigt logge ind i den delte CBC password manager.
* [ ] Jeg kan hente `cbc_hetzner` og SSH'e ind på serveren UDEN Johans hjælp.
* [ ] Jeg kan læse `/root/cbc-deploy-creds.txt`.
* [ ] Jeg kan logge ind i Hetzner Cloud Console og åbne noVNC.
* [ ] Jeg kan logge ind i Cloudflare-kontoen **"CBC IT v2"** og se zonen `cbcit.dk`.
* [ ] Jeg kan åbne Plesk-panelet via **`https://plesk-event.cbcit.dk`** (CF Access godkender min mail).
* [ ] Jeg kan logge ind i Brevo.
* [ ] Jeg kan logge ind i GitHub-kontoen `johanjohansen-cbc` (eller repos er flyttet til CBC-org).
* [ ] Jeg kan tilgå OneDrive-backuppen OG kender backup-krypteringspasswordet.
* [ ] Jeg kan logge ind i QuickPay (webshoppens betalinger).
* [ ] Jeg kan udføre en deploy (eller har læst og forstået `docs/05-deploy-workflow.md`).
* [ ] Jeg har adgang til driftsmanualen `_handover/drift/` (via det private GitHub-repo).
* [ ] Jeg kan læse `/root/cbc-hardening-2026-10/README.md` og forstår, hvad `cbc-web-egress-mode.sh status` viser.
* [ ] Jeg har sat Hetzner-snapshot-rutinen op på min egen maskine (eller som server-side job) med eget API-token, og mandagsmailen kommer til mig.
* [ ] Alle alarm-mails (§10) går til en adresse, jeg læser.
* [ ] §11 (organisatorisk break-glass) er udfyldt.

Når alle felter er krydset af, er bus-factor-risikoen reelt afdækket — ikke før.

---

_Vedligehold dette dokument sammen med stakken. Sidst opdateret 2026-10-27 (ajourført efter okt. 2026-hærdningen og fuld sikkerhedsscanning 26/10; verificeret mod live server, ekstern scan og Cloudflare-API). Forrige fulde revision 2026-07-20._ 