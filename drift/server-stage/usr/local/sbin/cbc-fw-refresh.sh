#!/bin/bash
# CBC — refresh Cloudflare IP ranges in the nftables origin-lock (cbc_fw cf4/cf6 sets).
# Safe by design: validates fetched data, only acts on change, atomic set-only update,
# never touches the chain/policy or fail2ban's table. Mails on change or failure.
# 2026-10-22 (blast-radius-serien): persistering omskrevet — tidligere blev HELE regelfilen
# genskrevet fra en indbygget skabelon UDEN output-/web_egress-chains (= egress-filteret ville
# forsvinde fra boot-filen ved naeste CF-aendring). Nu erstattes KUN 'elements = {...}'-linjerne
# for cf4/cf6 i den eksisterende fil, saa alle oevrige chains/sets bevares uaendret.
set -uo pipefail

FILE=/etc/nftables.d/cbc_fw.nft
LOG=/var/log/cbc-fw-refresh.log
ALERT=johan@cbcit.dk
V4URL=https://www.cloudflare.com/ips-v4
V6URL=https://www.cloudflare.com/ips-v6

log(){ printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; logger -t cbc-fw-refresh -- "$*"; }

notify(){ # $1=subject $2=body  (best-effort, never fails the script)
  [ -x /usr/sbin/sendmail ] || return 0
  printf 'To: %s\nSubject: %s\nContent-Type: text/plain; charset=UTF-8\n\n%s\n' \
    "$ALERT" "$1" "$2" | /usr/sbin/sendmail -t 2>/dev/null || true
}

fail(){
  log "ABORT: $*"
  notify "[CBC] firewall CF-IP refresh FEJLEDE" \
"Refresh afbrudt: $*

Firewall-reglerne er UAENDREDE (sikker tilstand). Se $LOG paa serveren."
  exit 1
}

# --- fetch ---
V4=$(curl -fsS --max-time 25 "$V4URL") || fail "curl v4 fejlede"
V6=$(curl -fsS --max-time 25 "$V6URL") || fail "curl v6 fejlede"

# --- validate: every non-empty line must be a CIDR; counts within sane bounds ---
v4re='^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'
v6re='^[0-9A-Fa-f:]+/[0-9]{1,3}$'
t4=$(printf '%s\n' "$V4" | grep -c .); n4=$(printf '%s\n' "$V4" | grep -cE "$v4re")
t6=$(printf '%s\n' "$V6" | grep -c .); n6=$(printf '%s\n' "$V6" | grep -cE "$v6re")
[ "$t4" = "$n4" ] && [ "$n4" -ge 5 ] && [ "$n4" -le 100 ] || fail "v4 validering fejlede ($n4/$t4 gyldige)"
[ "$t6" = "$n6" ] && [ "$n6" -ge 3 ] && [ "$n6" -le 60 ]  || fail "v6 validering fejlede ($n6/$t6 gyldige)"

# --- compare with live sets; do nothing if unchanged ---
NEW4=$(printf '%s\n' "$V4" | sort)
NEW6=$(printf '%s\n' "$V6" | sort)
CUR4=$(nft list set inet cbc_fw cf4 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | sort)
CUR6=$(nft list set inet cbc_fw cf6 2>/dev/null | grep -oiE '[0-9a-f:]+/[0-9]+' | sort)
if [ "$NEW4" = "$CUR4" ] && [ "$NEW6" = "$CUR6" ]; then
  log "no change ($n4 v4, $n6 v6)"
  exit 0
fi

# --- changed: patch ONLY the two 'elements = { ... }' lines in the existing file ---
CF4=$(printf '%s\n' "$V4" | paste -sd, -)
CF6=$(printf '%s\n' "$V6" | paste -sd, -)
TMP=$(mktemp)
awk -v cf4="$CF4" -v cf6="$CF6" '
  /^[[:space:]]*set[[:space:]]+cf4[[:space:]]*\{/ { cur="cf4" }
  /^[[:space:]]*set[[:space:]]+cf6[[:space:]]*\{/ { cur="cf6" }
  /^[[:space:]]*set[[:space:]]+[A-Za-z0-9_]+[[:space:]]*\{/ && $2 != "cf4" && $2 != "cf6" { cur="" }
  /^[[:space:]]*chain[[:space:]]/ { cur="" }
  /^[[:space:]]*elements[[:space:]]*=/ && cur=="cf4" { match($0,/^[[:space:]]*/); print substr($0,1,RLENGTH) "elements = { " cf4 " }"; done4=1; next }
  /^[[:space:]]*elements[[:space:]]*=/ && cur=="cf6" { match($0,/^[[:space:]]*/); print substr($0,1,RLENGTH) "elements = { " cf6 " }"; done6=1; next }
  { print }
  END { if (!done4 || !done6) exit 3 }
' "$FILE" > "$TMP" || { rm -f "$TMP"; fail "kunne ikke finde cf4/cf6 elements-linjer i $FILE"; }
nft -c -f "$TMP" || { rm -f "$TMP"; fail "ny nft-fil fejlede syntaks-check"; }
# sanity: alle chains fra den gamle fil skal stadig findes i den nye
for ch in $(grep -oE '^[[:space:]]*chain[[:space:]]+[A-Za-z0-9_]+' "$FILE" | awk '{print $2}'); do
  grep -qE "^[[:space:]]*chain[[:space:]]+$ch[[:space:]]*\{" "$TMP" || { rm -f "$TMP"; fail "chain $ch mangler i ny fil"; }
done

# --- atomic live update of ONLY the sets (no chain/policy disruption) ---
nft -f - <<EOF || { rm -f "$TMP"; fail "atomisk set-opdatering fejlede"; }
flush set inet cbc_fw cf4
add element inet cbc_fw cf4 { ${CF4} }
flush set inet cbc_fw cf6
add element inet cbc_fw cf6 { ${CF6} }
EOF

# --- persist for boot (backup old, install new) ---
cp -a "$FILE" "${FILE}.bak-$(date +%Y%m%d%H%M%S)"
install -m 644 "$TMP" "$FILE"
rm -f "$TMP"

log "UPDATED CF ranges (v4 ${n4}, v6 ${n6})"
notify "[CBC] firewall CF-IP liste opdateret" \
"Cloudflares IP-liste aendrede sig og origin-laasen blev opdateret automatisk.
v4: ${n4} ranges, v6: ${n6} ranges.
Backup af forrige regelfil: ${FILE}.bak-*"
exit 0
