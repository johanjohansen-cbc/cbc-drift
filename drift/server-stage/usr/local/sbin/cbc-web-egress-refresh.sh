#!/bin/bash
# CBC blast-radius 2026-10-22 — oploes allowlist-hostnavne og laeg IP'erne i nft-saettene
# web_allow4/web_allow6 (table inet cbc_fw) med timeout 8d. Idempotent; roerer ALDRIG chains.
# Persisterer sidst-kendte elementer til /etc/nftables.d/cbc_web_egress_elements.nft, som
# cbc-fw-apply.sh genindlaeser ved boot (saa web-uid'erne ikke staar uden allowlist til foerste timer-koersel).
set -uo pipefail
HOSTS=/etc/cbc-web-egress-hosts.txt
ELEM=/etc/nftables.d/cbc_web_egress_elements.nft
LOG=/var/log/cbc-web-egress-refresh.log
TTL=8d
RES=127.0.0.53

log(){ printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; logger -t cbc-web-egress-refresh -- "$*"; }

nft list set inet cbc_fw web_allow4 >/dev/null 2>&1 || { log "ABORT: set web_allow4 mangler (cbc_fw ikke indlaest?)"; exit 1; }
[ -r "$HOSTS" ] || { log "ABORT: $HOSTS mangler"; exit 1; }

declare -A V4 V6
nhosts=0; nfail=0
while IFS= read -r line || [ -n "$line" ]; do
  host=${line%%#*}; host=$(printf '%s' "$host" | tr -d '[:space:]')
  [ -z "$host" ] && continue
  nhosts=$((nhosts+1))
  a=$(dig +short +time=3 +tries=2 A "$host" "@$RES" 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$')
  b=$(dig +short +time=3 +tries=2 AAAA "$host" "@$RES" 2>/dev/null | grep -E '^[0-9a-fA-F:]+$' | grep ':')
  if [ -z "$a$b" ]; then log "WARN: $host kunne ikke oploeses (beholder evt. gamle IP'er til de udloeber)"; nfail=$((nfail+1)); continue; fi
  for ip in $a; do V4["$ip"]=1; done
  for ip in $b; do V6["$ip"]=1; done
done < "$HOSTS"

added=0; failed=0
TMP=$(mktemp)
for ip in "${!V4[@]}"; do
  if nft add element inet cbc_fw web_allow4 "{ $ip timeout $TTL }" 2>>"$LOG"; then added=$((added+1)); else failed=$((failed+1)); fi
  printf 'add element inet cbc_fw web_allow4 { %s timeout %s }\n' "$ip" "$TTL" >>"$TMP"
done
for ip in "${!V6[@]}"; do
  if nft add element inet cbc_fw web_allow6 "{ $ip timeout $TTL }" 2>>"$LOG"; then added=$((added+1)); else failed=$((failed+1)); fi
  printf 'add element inet cbc_fw web_allow6 { %s timeout %s }\n' "$ip" "$TTL" >>"$TMP"
done

# --- netvaerks-ranges (Google/Meta m.fl.) fra /etc/cbc-web-egress-ranges.txt -> interval-saet ---
RANGES=/etc/cbc-web-egress-ranges.txt
n4r=0; n6r=0
if [ -r "$RANGES" ]; then
  R4=$(sed 's/#.*//' "$RANGES" | tr -d ' \t' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$' | sort -u | paste -sd, -)
  R6=$(sed 's/#.*//' "$RANGES" | tr -d ' \t' | grep -E '^[0-9a-fA-F:]+/[0-9]{1,3}$' | sort -u | paste -sd, -)
  n4r=$(printf '%s' "$R4" | tr ',' '\n' | grep -c .); n6r=$(printf '%s' "$R6" | tr ',' '\n' | grep -c .)
  RT=$(mktemp)
  [ -n "$R4" ] && printf 'flush set inet cbc_fw web_allow_net4\nadd element inet cbc_fw web_allow_net4 { %s }\n' "$R4" >>"$RT"
  [ -n "$R6" ] && printf 'flush set inet cbc_fw web_allow_net6\nadd element inet cbc_fw web_allow_net6 { %s }\n' "$R6" >>"$RT"
  if [ -s "$RT" ]; then
    if nft -f "$RT" 2>>"$LOG"; then
      [ -n "$R4" ] && printf 'add element inet cbc_fw web_allow_net4 { %s }\n' "$R4" >>"$TMP"
      [ -n "$R6" ] && printf 'add element inet cbc_fw web_allow_net6 { %s }\n' "$R6" >>"$TMP"
    else
      log "WARN: ranges-saet kunne ikke indlaeses (gamle ranges bevaret)"; failed=$((failed+1))
    fi
  fi
  rm -f "$RT"
fi

if [ -s "$TMP" ] && nft -c -f "$TMP" 2>>"$LOG"; then
  install -m 644 "$TMP" "$ELEM"
fi
rm -f "$TMP"
log "ok: hosts=$nhosts fejl-oploesning=$nfail v4=${#V4[@]} v6=${#V6[@]} tilfoejet/opdateret=$added ranges-v4=$n4r ranges-v6=$n6r nft-fejl=$failed"
[ "$failed" -eq 0 ]
