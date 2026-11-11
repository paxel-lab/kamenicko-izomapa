#!/bin/sh
# Nahraje složku site/ do Cloudflare R2 (bucket mapovna-izomapa) přes rclone (S3 API).
#   ./nahrat.sh -n     zkouška: jen vypíše, co by se nahrálo a smazalo, nic neposílá
#   ./nahrat.sh        nahraje změněné soubory (porovnává kontrolní součty, takže po opravách
#                      jde nahoru jen to, co se změnilo), smaže na R2 soubory, které v site/ nejsou,
#                      a vyčistí mezipaměť Cloudflare pro izo.mapovna.app
#
# Postup po stavbě: ./postav.sh, python nastroje/plakat.py (plakáty site/plakat-*.webp), ./nahrat.sh
#
# Předpoklad: rclone s nastaveným vzdáleným úložištěm "izo" (rclone config), viz README, oddíl Hosting.
# Přístupové klíče jsou JEN v konfiguraci rclone na tomhle počítači (rclone config file), nikdy v repu.
# Token izomapa-zapis má mít práva Object Read & Write jen na bucket mapovna-izomapa.
# Čištění mezipaměti: token a zóna jsou v ~/.config/izomapa/cloudflare.env (mimo repo):
#   CF_ZONE_ID=...        ID zóny mapovna.app
#   CF_PURGE_TOKEN=...    token s právem Zone > Cache Purge (např. stávající mapovna-cache-purge)
set -e
cd "$(dirname "$0")"
REMOTE="${IZO_REMOTE:-izo}"          # název vzdáleného úložiště v rclone
BUCKET="${IZO_BUCKET:-mapovna-izomapa}"
HOST="${IZO_HOST:-izo.mapovna.app}"
ENVFILE="${IZO_CF_ENV:-$HOME/.config/izomapa/cloudflare.env}"
[ -f site/index.html ] || { echo "site/index.html neexistuje, nejdřív ./postav.sh"; exit 1; }
command -v rclone >/dev/null 2>&1 || { echo "rclone není nainstalovaný (winget install Rclone.Rclone)"; exit 1; }
rclone listremotes | grep -qx "$REMOTE:" || { echo "rclone nemá vzdálené úložiště '$REMOTE' (rclone config)"; exit 1; }
DRY=""; [ "$1" = "-n" ] && DRY="--dry-run" && echo "ZKOUŠKA: nic se neodešle"
[ -f site/plakat-1200.webp ] || echo "Pozor: chybí plakáty site/plakat-*.webp (python nastroje/plakat.py)"

# rclone nastaví Content-Type podle přípony (.webp, .png, .json, .html); R2 nezná výchozí index.html,
# ten řeší pravidlo Transform Rule v Cloudflare (viz README).
# Obrázky (.webp, .png) se mění jen při novém renderu: týden v prohlížeči. Web a data (.html, .json): 10 minut.
# Ostatní (.jpg, .svg, .webmanifest…): den. Cache Rule v Cloudflare drží okraj déle, po nahrání se čistí.
ZMENY="$(mktemp)"; trap 'rm -f "$ZMENY"' EXIT
COMMON="--s3-no-check-bucket --checksum --transfers 32 --checkers 64 --fast-list --stats 10s --stats-one-line $DRY"
# --combined: seznam změn (+ nový, * změněný, - smazaný), pro případné čištění po souborech
rclone sync site "$REMOTE:$BUCKET" $COMMON --combined "$ZMENY.a" \
  --exclude "*.html" --exclude "*.json" --exclude "robots.txt" --exclude "*.webp" --exclude "*.png" \
  --header-upload "Cache-Control: public, max-age=86400"
rclone sync site "$REMOTE:$BUCKET" $COMMON --combined "$ZMENY.b" \
  --include "*.webp" --include "*.png" \
  --header-upload "Cache-Control: public, max-age=604800"
# (copy místo sync: zastaralé .json/.html na R2 se samy nemažou, stačí je jednou smazat ručně)
rclone copy site "$REMOTE:$BUCKET" $COMMON --combined "$ZMENY.c" \
  --include "*.html" --include "*.json" --include "robots.txt" \
  --header-upload "Cache-Control: public, max-age=600"
cat "$ZMENY.a" "$ZMENY.b" "$ZMENY.c" 2>/dev/null | grep -v '^= ' > "$ZMENY" || true
rm -f "$ZMENY.a" "$ZMENY.b" "$ZMENY.c"

# Čištění mezipaměti Cloudflare po nahrání (ne při zkoušce, ne když nic nepřibylo).
if [ -n "$DRY" ]; then
  echo "Zkouška: mezipaměť se nečistí."
elif [ ! -s "$ZMENY" ]; then
  echo "Nic se nezměnilo, mezipaměť se nečistí."
elif [ ! -f "$ENVFILE" ]; then
  echo "Pozor: chybí $ENVFILE (CF_ZONE_ID, CF_PURGE_TOKEN), mezipaměť se nevyčistila."
else
  . "$ENVFILE"
  [ -n "$CF_ZONE_ID" ] && [ -n "$CF_PURGE_TOKEN" ] || { echo "$ENVFILE nemá CF_ZONE_ID a CF_PURGE_TOKEN"; exit 1; }
  API="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/purge_cache"
  purge() {  # $1 = JSON tělo; vrací 0 při success:true
    curl -s -X POST "$API" -H "Authorization: Bearer $CF_PURGE_TOKEN" -H "Content-Type: application/json" \
      --data "$1" | tee "$ZMENY.odpoved" | grep -q '"success":[ ]*true'
  }
  if purge "{\"hosts\":[\"$HOST\"]}"; then
    echo "Mezipaměť pro $HOST vyčištěna (podle hostitele)."
  else
    echo "Čištění podle hostitele selhalo ($(head -c 300 "$ZMENY.odpoved")), čistím seznam změněných souborů."
    # po dávkách po 30 adres (limit bezplatného tarifu na jedno volání)
    sed -n 's/^[+*-] //p' "$ZMENY" | sed "s#^#https://$HOST/#" | \
      awk 'BEGIN{n=0} {a[n++]=$0} END{for(i=0;i<n;i+=30){s="";for(j=i;j<i+30&&j<n;j++)s=s (s==""?"":",") "\"" a[j] "\""; print "{\"files\":[" s "]}"}}' | \
      while read -r BODY; do purge "$BODY" || { echo "Čištění souborů selhalo: $(head -c 300 "$ZMENY.odpoved")"; exit 1; }; done
    echo "Mezipaměť vyčištěna podle souborů."
  fi
  rm -f "$ZMENY.odpoved"
fi
echo "Hotovo. $( [ -n "$DRY" ] && echo '(zkouška)' ) Adresa: https://$HOST/"
