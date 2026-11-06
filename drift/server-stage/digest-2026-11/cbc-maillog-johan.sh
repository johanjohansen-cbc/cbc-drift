#!/bin/bash
# READ-ONLY (digest 2026-11): faktiske leveringer til johan@cbcit.dk seneste 14 dage, afsender -> antal.
# Supplement til cbc-mail-inventar.sh: sektion 3 dér greppede /var/log/mail.log* (findes ikke — Plesk logger til
# /var/log/maillog + maillog.processed). Postfix skriver from= og to= på hver sin linje -> join på queue-id.
# Skriver intet på serveren. Kør:  ssh cbc-prod 'bash -s' < cbc-maillog-johan.sh > 00-maillog-johan.txt 2>&1
LOGS=/var/log/maillog
echo "maillog-filer:"; ls -la "$LOGS"* 2>&1
dump() { local f; for f in "$LOGS".processed* "$LOGS"; do
  [ -e "$f" ] || continue
  case "$f" in (*.gz) zcat "$f" ;; (*) cat "$f" ;; esac
done 2>/dev/null; }
AWK='
  BEGIN { split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec",m," "); for(i=1;i<=12;i++) mon[m[i]]=i }
  { if (!match($0,/ [0-9A-F]{8,}: /)) next; q=substr($0,RSTART+1,RLENGTH-3)
    if (index($0," from=<")) { s=$0; sub(/.* from=</,"",s); sub(/>.*/,"",s); from[q]=s }
    if (index($0," to=<johan@cbcit.dk>") && index($0," status=")) {
      if ($1 ~ /^[0-9][0-9][0-9][0-9]-/) d=substr($1,1,10); else d=sprintf("%s-%02d-%02d",year,mon[$1],$2)
      st=$0; sub(/.* status=/,"",st); sub(/ .*/,"",st)
      cnt[(q in from ? from[q] : "?") "\t" st "\t" d]++ } }
  END { for (k in cnt) print k "\t" cnt[k] }'
DATA=$(dump | awk -v year="$(date +%Y)" "$AWK")
CUT=$(date -d '-14 days' +%F)
echo; echo "== afsender [status] -> antal (fra $CUT) =="
awk -F'\t' -v c="$CUT" '$3>=c {a[$1" ["$2"]"]+=$4; n+=$4} END {for(k in a) printf "%5d  %s\n",a[k],k; printf "%5d  TOTAL\n",n}' <<<"$DATA" | sort -rn
echo; echo "== pr. dag =="
awk -F'\t' -v c="$CUT" '$3>=c {a[$3]+=$4} END {for(k in a) print k, a[k]}' <<<"$DATA" | sort
echo; echo "== ældste/nyeste dato med johan@-levering i loggen =="; cut -f3 <<<"$DATA" | sort -u | sed -n '1p;$p'
