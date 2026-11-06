#!/bin/bash
# CBC daglig digest 2026-11-06: EN samlet driftsmail om dagen til johan@cbcit.dk (cron 07:30, /etc/cron.d/cbc-digest).
#
# Indhold: (1) beskeder spoolet siden sidst i /var/spool/cbc-digest/inbox (fra cbc-notify.sh digest og fra mails til
#          digest@server.cbcit.dk via cbc-digest-ingest.sh) + (2) live-status: Plesk-backup, opdateringer/patching,
#          sikkerhed (integrity, Imunify, fail2ban, egress), sites (HTTP, WP-cron, outbox), disk/load/mailkoe.
# Statuslinje: "Alt groent" eller "N punkter kraever opmaerksomhed" (punkterne listes oeverst).
# Efter afsendelse: spool -> archive/YYYY-MM-DD/ (slettes efter 30 dage) + ping til healthchecks.io ("digest").
#
# Brug:  cbc-digest.sh            normal koersel (cron)
#        cbc-digest.sh --test     send digesten NU med aktuelt indhold (emne "[TEST] ..."); arkiverer/pinger IKKE
#        cbc-digest.sh --dry-run  skriv HTML til stdout; sender/arkiverer/pinger IKKE
# Rollback: touch /etc/cbc-digest.disabled  (cbc-notify/ingest sender saa alt straks igen; digesten koerer stadig og
#           toemmer det der allerede ligger i spoolen). Fuld fjernelse: se README i server-stage/digest-2026-11.
set -uo pipefail
export LC_ALL=C.UTF-8 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

MODE=run
case "${1:-}" in --test) MODE=test;; --dry-run) MODE=dry;; "") ;; *) echo "brug: $0 [--test|--dry-run]" >&2; exit 2;; esac

TO=johan@cbcit.dk
FROM_ADDR=noreply@cbcit.dk
SPOOL=/var/spool/cbc-digest
INBOX=$SPOOL/inbox
ARCHIVE=$SPOOL/archive
LOG=/var/log/cbc-digest.log
HOST=$(hostname -f 2>/dev/null || hostname)
PHP=/opt/plesk/php/8.4/bin/php
WPCLI="$PHP -d memory_limit=512M /usr/local/bin/wp"
MAXLINES=40
PLESK_URL=https://plesk-event.cbcit.dk/
HC_URL=https://healthchecks.io/
NL=$'\n'
TEAL='#14798A'; GREEN='#5BAE3A'; AMBER='#C7781A'; GREY='#6B7378'; LINE='#D9DEE1'

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '%s [digest] %s\n' "$(ts)" "$*" >> "$LOG"; }
esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

# Mandag: vent (max 20 min) paa at advisory-watch' ugerapport er spoolet, saa den kommer med i fuld laengde
DOW=$(date +%u)
if [ "$MODE" = run ] && [ "$DOW" = 1 ]; then
  for _ in $(seq 1 40); do pgrep -f 'cbc-advisory-watch.sh weekly' >/dev/null || break; sleep 30; done
fi

# ---------------------------------------------------------------- status-akkumulatorer
ATTN=()                     # punkter der kraever opmaerksomhed (plain text)
declare -A SEC_HTML SEC_TXT  # sektion -> html-raekker / tekst
SECTIONS=("Backup" "Opdateringer og patching" "Sikkerhed" "Sites" "Server")

# row <sektion> <ok|warn|info> <label> <tekst>
row() {
  local sec=$1 st=$2 label=$3 txt=$4 badge col
  case "$st" in ok) badge=OK; col=$GREEN;; warn) badge=OBS; col=$AMBER; ATTN+=("$label: $txt");; *) badge=INFO; col=$GREY;; esac
  SEC_HTML[$sec]+="<tr><td valign=\"top\" style=\"padding:6px 8px 6px 0;width:44px;\"><span style=\"display:inline-block;background-color:$col;color:#ffffff;font-family:Arial,sans-serif;font-size:11px;font-weight:bold;line-height:18px;padding:0 6px;border-radius:3px;\">$badge</span></td><td valign=\"top\" style=\"padding:6px 8px 6px 0;width:150px;font-family:Arial,sans-serif;font-size:14px;color:#1F2A30;font-weight:bold;\">$(esc "$label")</td><td valign=\"top\" style=\"padding:6px 0;font-family:Arial,sans-serif;font-size:14px;line-height:20px;color:#1F2A30;\">$(esc "$txt" | sed 's/$/<br>/' | tr -d '\n' | sed 's/<br>$//')</td></tr>"$'\n'
  SEC_TXT[$sec]+="  [$badge] $label: $txt"$'\n'
}

# ---------------------------------------------------------------- 1) spool
mapfile -t FILES < <(find "$INBOX" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | sort)
declare -A MSG_HTML MSG_TXT MSG_N
job_section() {
  case "$1" in
    security-updates|advisory-watch|wp-integrity) echo "Opdateringer og patching";;
    egress-report|fw-refresh|web-egress-ranges|woo-order-watch) echo "Sikkerhed";;
    *) echo "Oevrige";;
  esac
}
for f in "${FILES[@]}"; do
  b=$(basename "$f" .txt); job=${b#*_}; job=${job%%_[0-9]*}; stamp=${b%%_*}
  when="${stamp:6:2}/${stamp:4:2} ${stamp:9:2}:${stamp:11:2}"
  subj=$(head -n1 "$f" | cut -c1-200); total=$(( $(wc -l < "$f") - 1 ))
  lim=$MAXLINES
  [ "$job" = advisory-watch ] && [ "$DOW" = 1 ] && grep -q 'tilstand: weekly' "$f" && lim=100000
  body=$(tail -n +2 "$f" | head -n "$lim" | cut -c1-500)
  more=""; [ "$total" -gt "$lim" ] && more="... ($((total-lim)) linjer mere i $ARCHIVE/$(date +%F)/$(basename "$f"))"
  sec=$(job_section "$job")
  MSG_N[$sec]=$(( ${MSG_N[$sec]:-0} + 1 ))
  MSG_HTML[$sec]+="<tr><td style=\"padding:10px 0 4px 0;font-family:Arial,sans-serif;font-size:14px;color:#1F2A30;\"><strong>$(esc "$subj")</strong><br><span style=\"font-size:12px;color:$GREY;\">$(esc "$job") &middot; $(esc "$when")</span></td></tr><tr><td style=\"padding:0 0 8px 0;\"><table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\"><tr><td style=\"background-color:#F2F4F5;border:1px solid $LINE;padding:10px;font-family:Consolas,'Courier New',monospace;font-size:12px;line-height:16px;color:#1F2A30;\"><pre style=\"margin:0;white-space:pre-wrap;word-wrap:break-word;font-family:Consolas,'Courier New',monospace;font-size:12px;\">$(esc "$body")${more:+
$(esc "$more")}</pre></td></tr></table></td></tr>"$'\n'
  MSG_TXT[$sec]+="--- $subj  ($job, $when)${NL}$(printf '%s\n' "$body" | sed 's/^/    /')${NL}${more:+    $more${NL}}"
done

# ---------------------------------------------------------------- 2) live-status
# Backup
BK=$(/usr/local/sbin/cbc-backup-check.sh -n 2>/dev/null); bkrc=$?
latest=$(ls -td /var/lib/psa/dumps/.discovered/backup_info_* 2>/dev/null | head -1)
age=""; [ -n "$latest" ] && age=" (alder $(( ($(date +%s) - $(stat -c %Y "$latest")) / 3600 )) t, sendt til OneDrive)"
if [ "$bkrc" = 0 ]; then row Backup ok "Plesk-backup" "Nattens backup OK${age}"; else row Backup warn "Plesk-backup" "${BK:-cbc-backup-check gav intet svar}"; fi
HCN=$(grep -cE '^[a-z]+=https://' /etc/cbc-healthchecks.conf 2>/dev/null || true)
HCJ=$(grep -oE '^[a-z]+=' /etc/cbc-healthchecks.conf 2>/dev/null | tr -d '=' | tr '\n' ' ')
row Backup info "Dead-man-ping" "$HCN job pinger healthchecks.io (${HCJ:-ingen}). Status ses kun paa healthchecks.io - udebliver et ping, mailer healthchecks selv."

# Opdateringer
AR=/var/lib/cbc-advisory/last-report.txt
if [ -r "$AR" ]; then
  arage=$(( ($(date +%s) - $(stat -c %Y "$AR")) / 3600 ))
  na=$(grep -c '^  \* ' "$AR" || true); nsec=$(grep '^  \* ' "$AR" | grep -c 'SIKKERHED?' || true)
  items=$(grep '^  \* ' "$AR" | sed -E 's/^  \* //; s/  ->  .*$//; s/\[SIKKERHED\? .*\]/[SIKKERHED?]/' | cut -c1-160 | sed 's/^/- /')
  if [ "$nsec" -gt 0 ]; then row "Opdateringer og patching" warn "Advisory-watch" "$nsec sikkerhedsmarkerede af $na afvigelser (rapport ${arage} t gammel):"$'\n'"$items"
  elif [ "$na" -gt 0 ]; then row "Opdateringer og patching" info "Advisory-watch" "$na afvigelser uden sikkerhedsflag (rapport ${arage} t gammel):"$'\n'"$items"
  else row "Opdateringer og patching" ok "Advisory-watch" "Ingen afvigelser (rapport ${arage} t gammel)"; fi
  [ "$arage" -gt 50 ] && row "Opdateringer og patching" warn "Advisory-watch" "Rapporten er ${arage} timer gammel - koerer cron-jobbet?"
else
  row "Opdateringer og patching" warn "Advisory-watch" "$AR mangler"
fi
SL=/var/log/cbc-security-updates.log
lastend=$(grep -E ' END: ' "$SL" 2>/dev/null | tail -1 | cut -c1-19)
if [ -n "$lastend" ]; then
  slage=$(( ($(date +%s) - $(date -d "$lastend" +%s)) / 3600 ))
  errs=$(awk -v s="$(date -d '-24 hours' '+%Y-%m-%d %H:%M:%S')" 'substr($0,1,19)>=s && / ERROR/' "$SL" | wc -l)
  upg=$(awk -v s="$(date -d '-24 hours' '+%Y-%m-%d %H:%M:%S')" 'substr($0,1,19)>=s && / END: [1-9]/' "$SL" | sed -E 's/^(.{16}).{3} END: ([0-9]+ pakke\(r\) aendret).*/\2 (\1)/' | paste -sd ';' | sed 's/;/; /g')
  if [ "$errs" -gt 0 ]; then row "Opdateringer og patching" warn "Sikkerhedsopdateringer" "$errs ERROR-linjer i $SL seneste 24 t"
  elif [ "$slage" -gt 6 ]; then row "Opdateringer og patching" warn "Sikkerhedsopdateringer" "Seneste koersel for $slage t siden (forventet hver 4. t)"
  else row "Opdateringer og patching" ok "Sikkerhedsopdateringer" "Koerer hver 4. t, seneste $lastend. Seneste 24 t: ${upg:-intet opgraderet}"; fi
else row "Opdateringer og patching" warn "Sikkerhedsopdateringer" "Ingen END-linje i $SL"; fi
if [ -f /var/run/reboot-required ]; then
  row "Opdateringer og patching" warn "Genstart" "Paakraevet ($(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null)) - auto-reboot 04:00 tager den"
else row "Opdateringer og patching" ok "Genstart" "Ingen genstart afventer"; fi
nupg=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)
row "Opdateringer og patching" info "apt" "$nupg pakke(r) kan opgraderes (ikke-security haandteres ikke automatisk)"

# Sikkerhed
IL=/var/log/cbc-wp-integrity.log
il=$(tail -1 "$IL" 2>/dev/null)
ilage=$(( ($(date +%s) - $(stat -c %Y "$IL" 2>/dev/null || echo 0)) / 3600 ))
if [ -z "$il" ]; then row Sikkerhed warn "WP-integritet" "Ingen log ($IL)"
elif [ "$ilage" -gt 26 ]; then row Sikkerhed warn "WP-integritet" "Seneste koersel $ilage t siden (timer 05:17 dagligt)"
elif echo "$il" | grep -q 'alert=1'; then row Sikkerhed warn "WP-integritet" "Checksum-AFVIGELSE i seneste koersel - se /var/log/cbc-wp-integrity-last.txt"
else row Sikkerhed ok "WP-integritet" "Checksums OK paa alle tre sites (${il:1:19})"; fi
IMJ=$(imunify360-agent malware malicious list --json 2>/dev/null | grep -oE '"malicious_count": [0-9]+' | grep -oE '[0-9]+$')
IMS=$(imunify360-agent malware on-demand list --limit 50 --json 2>/dev/null | "$PHP" -r '$d=json_decode(stream_get_contents(STDIN),true); $n=null; foreach(($d["items"]??[]) as $i){ if($n===null||$i["created"]>$n["created"]) $n=$i; } if($n){ echo (int)((time()-$n["created"])/3600), " ", $n["scan_status"], " ", (int)$n["total_malicious"]; }' 2>/dev/null)
read -r ims_h ims_st ims_mal <<<"${IMS:-}"
if [ -z "$IMJ" ]; then row Sikkerhed warn "Imunify" "Kunne ikke laese Imunify-status"
elif [ "$IMJ" -gt 0 ]; then row Sikkerhed warn "Imunify" "$IMJ fund paa listen over ondsindede filer"
elif [ -n "${ims_h:-}" ] && [ "$ims_h" -gt 50 ]; then row Sikkerhed warn "Imunify" "0 fund, men seneste planlagte scan er $ims_h t gammel (skal koere dagligt 03:00)"
else row Sikkerhed ok "Imunify" "0 fund. Seneste scan ${ims_h:-?} t siden (${ims_st:-?})"; fi
F2B=""; F2BT=0
for j in $(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:\s*//p' | tr ',' ' '); do
  cur=$(fail2ban-client status "$j" 2>/dev/null | sed -n 's/.*Currently banned:\s*//p')
  [ "${cur:-0}" -gt 0 ] && F2B+="$j $cur, "; F2BT=$((F2BT + ${cur:-0}))
done
row Sikkerhed info "fail2ban" "$F2BT IP'er bandlyst lige nu${F2B:+ (${F2B%, })}"
EM=$(nft -a list chain inet cbc_fw web_egress 2>/dev/null | grep -oE 'cbc-egress-mode: [a-z-]+' | awk '{print $2}')
ED=$(journalctl -k --since '-24 hours' 2>/dev/null | grep -c 'cbc-egress-drop:' || true)
if [ "$EM" = enforce ]; then row Sikkerhed info "Egress-filter" "enforce, $ED droppede pakker seneste 24 t (detaljer i egress-rapporten)"
else row Sikkerhed warn "Egress-filter" "Tilstand '${EM:-UKENDT}' (forventet enforce), $ED hits seneste 24 t"; fi

# Sites
ORIGIN_IP=$(getent ahostsv4 server.cbcit.dk 2>/dev/null | awk 'NR==1{print $1}'); ORIGIN_IP=${ORIGIN_IP:-178.104.70.94}
for u in https://event.cbcit.dk/ https://www.cbcit.dk/ https://www.datagaarden.dk/; do
  h=${u#https://}; h=${h%%/*}
  code=$(curl -ksS -o /dev/null -L --max-time 20 --resolve "$h:443:$ORIGIN_IP" -w '%{http_code}' -A 'cbc-digest/1.0' "$u" 2>/dev/null || echo FEJL)
  if [ "$code" = 200 ]; then row Sites ok "$h" "HTTP 200 (origin)"; else row Sites warn "$h" "HTTP $code (origin $ORIGIN_IP)"; fi
done
for s in "event.cbcit.dk event.cbcit.dk_x3pjx5okzbn" "cbcit.dk cbcitdk" "datagaarden.dk datagaardendk"; do
  read -r site user <<<"$s"
  out=$(timeout 120 su -s /bin/bash "$user" -c "$WPCLI --path=/var/www/vhosts/$site/httpdocs --skip-themes --skip-plugins=wordfence eval-file /usr/local/lib/cbc-digest/wp-status.php" 2>/dev/null)
  if [ -z "$out" ]; then row Sites warn "$site WP" "wp-status gav intet svar"; continue; fi
  g() { printf '%s\n' "$out" | sed -n "s/^$1=//p" | head -1; }
  ov=$(g cron_overdue); oh=$(g cron_oldest_h); wv=$(g wp_version)
  if [ "${ov:-0}" -gt 0 ] && [ "${oh:-0}" -ge 2 ]; then row Sites warn "$site WP-cron" "$ov events over 1 t forsinket (aeldste $oh t) - WP $wv"
  else row Sites ok "$site WP-cron" "Ingen haengende cron-events - WP $wv"; fi
  if [ "$site" = event.cbcit.dk ]; then
    pend=$(g outbox_pending); f24=$(g outbox_failed24); ls_=$(g outbox_last_sent_min); rn=$(g reminder_next)
    probs=$(printf '%s\n' "$out" | sed -n 's/^problem=//p')
    if [ -n "$probs" ]; then row Sites warn "event cron-sundhed" "$probs"
    else row Sites ok "event cron-sundhed" "Plugin-crons OK (Cron_Health_Notice). Naeste reminder-koersel: $rn"; fi
    st=info; [ "${f24:-0}" -gt 0 ] && st=warn
    case "${ls_:-}" in ''|-) lsx="aldrig";; *) if [ "$ls_" -ge 2880 ]; then lsx="$((ls_/1440)) dage siden"; elif [ "$ls_" -ge 120 ]; then lsx="$((ls_/60)) t siden"; else lsx="$ls_ min siden"; fi;; esac
    row Sites "$st" "event outbox" "${pend:-?} i koe, ${f24:-?} permanent fejlede seneste 24 t, seneste afsendte mail: $lsx"
  fi
done

# Server
DU=$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}'); DF=$(df -h / | awk 'NR==2{print $4}')
if [ "${DU:-0}" -ge 85 ]; then row Server warn "Disk /" "${DU}% brugt, $DF fri"; else row Server ok "Disk /" "${DU}% brugt, $DF fri"; fi
LA=$(cut -d' ' -f1-3 /proc/loadavg); NP=$(nproc)
row Server info "Load" "$LA (${NP} kerner), oppe $(uptime -p | sed 's/^up //')"
MQ=$(mailq 2>/dev/null | tail -1)
if echo "$MQ" | grep -qi 'empty'; then row Server ok "Postfix-koe" "Tom"
else row Server warn "Postfix-koe" "$MQ"; fi
if postconf -h mydestination 2>/dev/null | grep -qw 'server.cbcit.dk'; then row Server ok "Digest-alias" "digest@server.cbcit.dk leveres lokalt"
else row Server warn "Digest-alias" "server.cbcit.dk mangler i Postfix mydestination - mails til digest@ gaar IKKE i digesten (Plesk kan have regenereret main.cf)"; fi
NOB=$(find "$SPOOL/outbox" -type f -name '*.msg' 2>/dev/null | wc -l)
if [ "$NOB" -gt 0 ]; then row Server warn "Alarm-outbox" "$NOB alarm(er) blev ikke sendt - se $SPOOL/outbox(/failed) og $LOG"
elif ! systemctl is-active --quiet cbc-digest-alert.path; then row Server warn "Alarm-outbox" "cbc-digest-alert.path er ikke aktiv - alarmer fra digest@ sendes ikke straks"; fi

# ---------------------------------------------------------------- 3) byg mail
DAYS=(mandag tirsdag onsdag torsdag fredag loerdag soendag)
DAYS_HTML=(mandag tirsdag onsdag torsdag fredag lørdag søndag)
MONTHS=(januar februar marts april maj juni juli august september oktober november december)
DNAME=${DAYS_HTML[$((DOW-1))]}; DNUM=$(date +%-d); MNAME=${MONTHS[$(( $(date +%-m) - 1 ))]}; YEAR=$(date +%Y)
NATT=${#ATTN[@]}
if [ "$NATT" = 0 ]; then STATUS="Alt grønt"; SCOL=$GREEN
elif [ "$NATT" = 1 ]; then STATUS="1 punkt kræver opmærksomhed"; SCOL=$AMBER
else STATUS="$NATT punkter kræver opmærksomhed"; SCOL=$AMBER; fi
NMSG=${#FILES[@]}
SUBJECT="CBC Drift $DNAME $DNUM. $MNAME: $STATUS"
[ "$MODE" = test ] && SUBJECT="[TEST] $SUBJECT"

button() { # $1 url $2 tekst
  cat <<EOB
<td align="center" style="padding:0 6px;">
<!--[if mso]><v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" xmlns:w="urn:schemas-microsoft-com:office:word" href="$1" style="height:42px;v-text-anchor:middle;width:190px;" arcsize="10%" stroke="f" fillcolor="$TEAL"><w:anchorlock/><center style="color:#ffffff;font-family:Arial,sans-serif;font-size:15px;font-weight:bold;">$2</center></v:roundrect><![endif]-->
<!--[if !mso]><!-- --><a href="$1" style="background-color:$TEAL;border-radius:4px;color:#ffffff;display:inline-block;font-family:Arial,sans-serif;font-size:15px;font-weight:bold;line-height:42px;text-align:center;text-decoration:none;width:190px;-webkit-text-size-adjust:none;mso-hide:all;">$2</a><!--<![endif]-->
</td>
EOB
}
section_head() {
  printf '<tr><td style="padding:22px 28px 0 28px;"><table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr><td style="font-family:Arial,sans-serif;font-size:17px;font-weight:bold;color:%s;padding-bottom:6px;border-bottom:1px solid %s;">%s</td></tr></table></td></tr>\n' "$TEAL" "$LINE" "$(esc "$1")"
}

HTML=$(
cat <<EOH
<!DOCTYPE html>
<html lang="da" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="x-apple-disable-message-reformatting"><title>$(esc "$SUBJECT")</title>
<!--[if mso]><noscript><xml><o:OfficeDocumentSettings><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml></noscript><![endif]-->
</head>
<body style="margin:0;padding:0;background-color:#F4F6F7;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#F4F6F7;"><tr><td align="center" style="padding:20px 10px;">
<table role="presentation" width="640" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:640px;background-color:#ffffff;border:1px solid $LINE;">
<tr><td style="background-color:$TEAL;padding:22px 28px;">
<div style="font-family:Arial,sans-serif;font-size:24px;font-weight:bold;color:#ffffff;">CBC Drift</div>
<div style="font-family:Georgia,'Times New Roman',serif;font-style:italic;font-size:16px;color:#E3F1F3;padding-top:4px;">$DNAME $DNUM. $MNAME $YEAR &middot; server.cbcit.dk</div>
</td></tr>
<tr><td style="background-color:$SCOL;padding:14px 28px;font-family:Arial,sans-serif;font-size:17px;font-weight:bold;color:#ffffff;">$(esc "$STATUS")</td></tr>
EOH
if [ "$NATT" -gt 0 ]; then
  printf '<tr><td style="padding:14px 28px 0 28px;"><table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0" style="border-left:4px solid %s;background-color:#FBF4EC;">\n' "$AMBER"
  for a in "${ATTN[@]}"; do printf '<tr><td style="padding:6px 12px;font-family:Arial,sans-serif;font-size:14px;line-height:20px;color:#1F2A30;">%s</td></tr>\n' "$(esc "$a" | sed 's/$/<br>/' | tr -d '\n' | sed 's/<br>$//')"; done
  printf '</table></td></tr>\n'
fi
for sec in "${SECTIONS[@]}"; do
  section_head "$sec"
  printf '<tr><td style="padding:4px 28px 0 28px;"><table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0">\n%s</table></td></tr>\n' "${SEC_HTML[$sec]:-}"
  if [ -n "${MSG_HTML[$sec]:-}" ]; then
    printf '<tr><td style="padding:6px 28px 0 28px;font-family:Arial,sans-serif;font-size:13px;color:%s;">Beskeder fra jobs (%s)</td></tr>\n' "$GREY" "${MSG_N[$sec]}"
    printf '<tr><td style="padding:0 28px;"><table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0">\n%s</table></td></tr>\n' "${MSG_HTML[$sec]}"
  fi
done
section_head "Øvrige meddelelser"
if [ -n "${MSG_HTML[Oevrige]:-}" ]; then
  printf '<tr><td style="padding:0 28px;"><table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0">\n%s</table></td></tr>\n' "${MSG_HTML[Oevrige]}"
else
  printf '<tr><td style="padding:8px 28px 0 28px;font-family:Arial,sans-serif;font-size:14px;color:%s;">Ingen øvrige meddelelser siden sidst.</td></tr>\n' "$GREY"
fi
cat <<EOH
<tr><td align="center" style="padding:28px 22px 8px 22px;"><table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
$(button "$PLESK_URL" "Åbn Plesk")
$(button "$HC_URL" "Healthchecks")
</tr></table></td></tr>
<tr><td style="padding:18px 28px 22px 28px;font-family:Arial,sans-serif;font-size:12px;line-height:18px;color:$GREY;border-top:1px solid $LINE;">Genereret af cbc-digest.sh på server.cbcit.dk &middot; rollback: touch /etc/cbc-digest.disabled<br>$NMSG besked(er) fra spoolen &middot; arkiv: $ARCHIVE &middot; log: $LOG</td></tr>
</table>
</td></tr></table>
</body></html>
EOH
)

TEXT="CBC Drift - $DNAME $DNUM. $MNAME $YEAR - server.cbcit.dk
STATUS: $STATUS
$( [ "$NATT" -gt 0 ] && printf '  ! %s\n' "${ATTN[@]}" )
"
for sec in "${SECTIONS[@]}"; do
  TEXT+="
== $sec ==
${SEC_TXT[$sec]:-}${MSG_TXT[$sec]:+
${MSG_TXT[$sec]}}"
done
TEXT+="
== Oevrige meddelelser ==
${MSG_TXT[Oevrige]:-  Ingen oevrige meddelelser siden sidst.}

Plesk: $PLESK_URL
Healthchecks: $HC_URL
Genereret af cbc-digest.sh paa server.cbcit.dk - rollback: touch /etc/cbc-digest.disabled"

if [ "$MODE" = dry ]; then printf '%s\n' "$HTML"; printf '\n<!-- PLAIN TEXT\n%s\n-->\n' "$TEXT"; exit 0; fi

# ---------------------------------------------------------------- 4) send
B="cbc-digest-$(date +%s)-$$"
ENC_SUBJ=$(printf '%s' "$SUBJECT" | "$PHP" -r 'echo mb_encode_mimeheader(stream_get_contents(STDIN), "UTF-8", "B", "\n");')
{
  printf 'From: CBC Drift <%s>\nTo: %s\nSubject: %s\nMIME-Version: 1.0\nX-CBC-Job: digest\n' "$FROM_ADDR" "$TO" "$ENC_SUBJ"
  printf 'Content-Type: multipart/alternative; boundary="%s"\n\nThis is a multi-part message in MIME format.\n\n' "$B"
  printf -- '--%s\nContent-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: base64\n\n' "$B"
  printf '%s\n' "$TEXT" | base64 -w 76
  printf -- '\n--%s\nContent-Type: text/html; charset=UTF-8\nContent-Transfer-Encoding: base64\n\n' "$B"
  printf '%s\n' "$HTML" | base64 -w 76
  printf -- '\n--%s--\n' "$B"
} | /usr/sbin/sendmail -i -f "$FROM_ADDR" "$TO"
rc=$?
log "$MODE: sendt (rc=$rc) '$SUBJECT' - $NMSG spool-besked(er), $NATT punkt(er)"
[ "$rc" = 0 ] || exit "$rc"
[ "$MODE" = test ] && exit 0

# ---------------------------------------------------------------- 5) arkivér + oprydning + dead-man-ping
if [ "$NMSG" -gt 0 ]; then
  DEST="$ARCHIVE/$(date +%F)"; mkdir -p "$DEST" && chmod 700 "$DEST"
  mv -f -- "${FILES[@]}" "$DEST/" && log "arkiveret $NMSG fil(er) -> $DEST"
fi
find "$ARCHIVE" -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf -- {} + 2>/dev/null
/usr/local/sbin/cbc-hc-ping.sh digest 0
exit 0
