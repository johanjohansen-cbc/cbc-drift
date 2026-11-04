# server-stage — spejl af `/root/cbc-hardening-2026-10/stage/`

Kopi af stage-mappen fra `server.cbcit.dk`, hentet read-only 2026-11-04 med
`scp -r cbc-prod:/root/cbc-hardening-2026-10/stage`. Formål: hærdningslaget
følger ikke med OneDrive-backuppen (05 §2.3), så kopierne skal også findes uden
for serveren.

- Gennemgået for hemmeligheder før commit (ingen passwords, tokens eller nøgler).
- Stien under mappen svarer til stien på serveren (fx `usr/local/sbin/…` →
  `/usr/local/sbin/…`). `apply-step*.sh`, `finish-step2.sh` og
  `updates-2026-10-23/install.sh` er engangs-scripts fra 22.–23. oktober 2026.
- **Øjebliksbillede fra 22.–23. oktober 2026.** Ved spejlingen var alle filer
  under `etc/` og `usr/` identiske med serverens live-version (md5),
  **undtagen `etc/cbc-web-egress-hosts.txt`**, som er udvidet på serveren siden.
  Hent den live ved genopbygning.
- Mappen dækker ikke hele server-level-laget. Resten (sshd-drop-in og
  SFTP-Match-blokke, `cbc-origin-guard.conf`, Postfix, Imunify-skema, øvrige
  `cbc-*`-timere, mu-plugins m.m.) er beskrevet i 05 §2.3 og
  `/root/cbc-hardening-2026-10/README.md`.
