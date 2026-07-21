# 07 — Break-Glass: Adgang til CBC-produktionsserveren hvis den driftsansvarlige falder bort

**Status:** Successions-/katastrofe-dokument ("bus factor"). Oprettet 2026-06-15 · **Opdateret 2026-07-20** (post-prod-dag: CF Access/Tunnel, ny Cloudflare-konto, alle tre sites på boksen, verificeret mod live server + Cloudflare-dashboard).  
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
| Web-panel | Plesk Obsidian 18.0.78.x | På serveren, port 8443. **Primær adgang: `https://plesk-event.cbcit.dk`** (Cloudflare Access → tunnel `cbc-plesk` → localhost:8443). Fallback: SSH-tunnel (`ssh -L 8443:localhost:8443 cbc-prod`). Port 8443 er IKKE åben i firewallen udefra. |
| Web-stack | nginx → Apache → PHP-FPM (plesk-php84) | På serveren |
| Sites på boksen | **event.cbcit.dk** (WP 7.0.1, frosset til efter konferencen, plugin cbc-event-planner + tema cbc-child) · **cbcit.dk** (WP 7.0 + **WooCommerce-webshop m. QuickPay-betalingsgateway**) · **datagaarden.dk** (WP 7.0.1, bag Kents load balancer — IKKE Cloudflare) | /var/www/vhosts/<domæne>/httpdocs |
| Kode-leverance | Self-hosted bare git repo + privat GitHub-mirror | Server /var/git/*.git + GitHub johanjohansen-cbc |
| Udgående mail | Postfix → Brevo SMTP-relay (port 587) | Brevo Free-plan; SASL-creds på serveren |
| Backup | Plesk Backup Manager → Microsoft OneDrive (M365) | OneDrive, retention 7 dage |
| Edge/sikkerhed | Cloudflare (proxied + WAF + Access) + Hetzner Cloud Firewall `cbc-edge` (id 11085732) + host-nftables `cbc_fw` + origin-guard | Cloudflare + Hetzner + serveren |



**Vigtigt:** Der findes **ingen staging-server** — der deployes direkte til prod via git (med backup + verifikation). Local by Flywheel på Johans maskine er dev-sandkassen. **datagaarden.dk** når serveren via Kents load balancer (185.21.232.10-12, firewall-regel `KENTS-LB-TEMP`) — ændringer dér koordineres med Kent (§11).

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

**Hvordan får en efterfølger adgang til vault'et?**  
Alle har adgang via safe notes i Roboform.

---

## 3\. Adgangs-topologien (hvem/hvad kan komme ind)

For at undgå misforståelser:

* **Der findes ingen separat "Claude"-adgang.** Al automatisering (Claude Code-værktøjet) kører gennem Johans maskine med Johans nøgle. Forsvinder Johans maskine, forsvinder den vej — men serveren er uberørt og tilgås med nøglen fra vault'et.
* **Serverens `/root/.ssh/authorized_keys` indeholder KUN nøglen `cbc_hetzner`.** Det er den eneste SSH-vej ind.
* **Password-login over SSH er slået FRA** (`PasswordAuthentication no`). Root-OS-passwordet virker derfor KUN på Hetzners web-konsol (noVNC) — som er den ultimative out-of-band redning hvis nøglen tabes (§8).
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
| Host-firewall regler | /etc/nftables.d/cbc_fw.nft (+ .fallback) |
| Brevo SMTP-creds | /etc/postfix/sasl_passwd (600, postmap'd) |
| Hærdnings-drop-ins | /etc/ssh/sshd_config.d/99-cbc-hardening.conf, /etc/sysctl.d/99-cbc-hardening.conf |



---

## 6\. De eksterne konti — verificér ejerskab

Serveren kan genskabes; men disse eksterne tjenester er kritiske og skal kontrolleres af CBC, ikke af en privatperson. Tjek hver:

### 6.1 Hetzner Cloud (serveren selv)

* Konsol: [https://console.hetzner.cloud](https://console.hetzner.cloud) — projekt indeholder server `cbc-server` (id `135078172`) + firewall `cbc-edge` (id `11085732`).
* **noVNC-konsol** herfra er den ultimative redning (§8).
* API-tokens: lav ad hoc Read&Write-token ved behov, **slet den bagefter** (ingen token gemmes permanent).

### 6.2 Cloudflare (DNS + edge-proxy + Access) — konto **"CBC IT v2"**

* Zonen `cbcit.dk` (Pro-plan, 59 records). `event.cbcit.dk` + `cbcit.dk` er **proxied** A-records (`178.104.70.94`, orange sky).
* ⚠️ **Zone-SSL-mode = "Full" og er DELT med ~18 andre CBC-sites på `185.21.232.10`. MÅ ALDRIG ændres** (se §9).
* **Zero Trust/Access:** app "CBC Plesk Panel" → `plesk-event.cbcit.dk` → tunnel `cbc-plesk` → serverens localhost:8443. Policy "Allow cbcit.dk", session 24 t, team `fancy-sound-8625.cloudflareaccess.com`. Det er den PRIMÆRE Plesk-adgang.
* **WAF:** Cloudflare Managed Ruleset aktiv + Super Bot Fight Mode + rate-limit på `/auth/`.
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

### 6.8 Kent / ekstern load balancer (datagaarden.dk)

* `datagaarden.dk` frontes af Kents load balancer (`185.21.232.10-12`) — IKKE
  Cloudflare. Plesk BIND på serveren er authoritative DNS for domænet.
* Firewallen har en dedikeret accept-regel (`KENTS-LB-TEMP`, 443). Ændringer i
  det spor koordineres med Kent: **Kent Grady — kgrady@kobalt.dk** (Kobalt er
  også CF-org-admin-kontakten i §11 og forklarer `spf1.kobalt.dk` i SPF-historikken).
* ⚠️ **Aftalen med Kobalt OPHØRER 2026-12-31.** Derefter forsvinder Kents LB som
  fronting for datagaarden.dk. Inden da skal datagaarden enten (a) flyttes bag
  Cloudflare som de øvrige sites, eller (b) have anden fronting. Planlæg i
  efteråret 2026 — efter konferencen, før december.

---

## 7\. Daglig drift — hvor runbooks ligger

Den løbende drift er dokumenteret to steder:

* **`drift/00–06` i dette repo** — den samlede tekniske driftsmanual for HELE
  serveren (arkitektur, firewall, CF-lag, alle tre sites, backup, runbooks,
  gotchas). Verificeret mod live server + Cloudflare 2026-07-20. **Start dér.**
  Kanonisk hjem: privat GitHub-repo **`johanjohansen-cbc/cbc-drift`** (dette
  dokument ligger samme sted — arbejdskopi i `app/public/_handover/` på Johans
  Local-maskine).
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

1. Provisionér ny Hetzner CPX32 + Plesk Obsidian + PHP 8.4\.
2. Hent seneste backup fra **OneDrive** via Plesk Backup Manager (kræver backup-krypteringspasswordet fra vault).
3. Gendan filer + DB. Genskab `wp-config.php`-konstanter, `.htaccess`, host-firewall (`cbc_fw.nft`), Brevo-relay (`sasl_passwd`).
4. Peg Cloudflare A-record mod ny IP (origin-låsen i firewall skal også opdateres til ny IP).
5. Full restore-drill til scratch-server er den anbefalede øvelse at have gjort PÅ FORHÅND — **dette er pt. ikke gennemført** (åbent punkt).

### 8.3 Kun koden skal genskabes

Koden findes tre steder: serverens bare repo (`/var/git/`), GitHub-mirror (`johanjohansen-cbc`), og Johans Local-maskine. Klon fra GitHub hvis serveren er væk.

---

## 9\. Må ALDRIG ændres (foot-guns)

Disse kan vælte prod — og nogle rammer langt bredere end dette ene site:

1. **Cloudflare zone-wide SSL-mode** (pt. "Full"). Den er **DELT med ~18 andre CBC-live-sites** på samme origin-IP (`185.21.232.10`). Ændrer du den, kan du tage alle de andre sites ned. Rør den aldrig.
2. **fail2bans nftables-tabel** (`table ip filter`). Host-firewallen bruger en SEPARAT tabel (`table inet cbc_fw`) netop for ikke at kollidere. Kør ALDRIG `nft flush ruleset`.
3. **Postfix `inet_interfaces`** — skal være `loopback-only`. Plesk kan nulstille den til `all` ved `plesk repair mail`; tjek `postconf -h inet_interfaces` hvis mail-porte pludselig er åbne.
4. **Egress-firewall** — udgående trafik er default-drop. Tilføjer du en ny integration på en skæv port, bliver den tavst droppet; tjek `journalctl -k | grep egress-drop` og åbn porten i `output`-chain i `cbc_fw.nft`.
5. **Firewall-ændringer** — kør ALTID med en "dead-man switch" (`systemd-run --on-active=300 ... nft delete table inet cbc_fw`) FØR du applyer, test frisk SSH, og annullér dead-man først når du er sikker. Ellers kan en regelfejl låse dig ude.
6. **WP/PHP-version** — WP er pinned til **7.0.1**, PHP til 8.4, **FRYS til efter konferencen (september 2026)**. Major-opgraderinger testes på Local FØRST.
7. **Nye Plesk-subscriptions SKAL have incoming mail slået fra** (`plesk bin subscription -u <domæne> -mail_service false`) — ellers **kaprer** den nye subscription MX/mail-leveringen for hele `@cbcit.dk` (som ligger på Microsoft 365). Dyrt lært.
8. **Origin-guard** (`/etc/nginx/conf.d/cbc-origin-guard.conf`) — geo-blok der giver 403 til enhver origin-forbindelse der ikke kommer fra Cloudflare/loopback. `datagaarden.dk` er BEVIDST undtaget (nås via Kents LB). Slet den ikke, og tilføj aldrig datagaarden til den.
9. **`KENTS-LB-TEMP`-firewall-reglen** (443 fra 185.21.232.10-12) — fjernes ikke uden koordinering med Kent (§6.8).

---

## 10\. Vedligehold nogen skal huske

* **Det meste passer sig selv:** OS-sikkerhedsopdateringer (unattended-upgrades, auto-reboot 04:00), Plesk-komponenter, fail2ban, ModSecurity, Imunify.
* **WordPress core/plugin-opdateringer er IKKE automatiske** (bevidst — `DISALLOW_FILE_MODS`). Et notify-script mailer `johan@cbcit.dk` ugentligt hvis noget venter. **→ Skift denne notify-email til en CBC-fælles/drifts-adresse**, ellers forsvinder beskederne med Johan. (Script: `/var/www/vhosts/event.cbcit.dk/cbc-update-notify.php`.)
* **Brevo Free = 300 mails/dag.** Ved et større event kan loftet rammes — overvåg.
* **Backups:** verificér jævnligt at OneDrive-backups faktisk skrives (Plesk Backup Manager-log).

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
* [ ] §11 (organisatorisk break-glass) er udfyldt.

Når alle felter er krydset af, er bus-factor-risikoen reelt afdækket — ikke før.

---

_Vedligehold dette dokument sammen med stakken. Sidst opdateret 2026-07-20 (fuld post-prod-dag-revision, verificeret mod live server + Cloudflare-dashboard)._ 