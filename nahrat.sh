#!/bin/sh
# Nahraje složku site/ do Cloudflare R2 (bucket mapovna-izomapa) přes rclone (S3 API).
#   ./nahrat.sh -n     zkouška: jen vypíše, co by se nahrálo a smazalo, nic neposílá
#   ./nahrat.sh        nahraje změněné soubory (porovnává kontrolní součty, takže po opravách
#                      jde nahoru jen to, co se změnilo) a smaže na R2 soubory, které v site/ nejsou
#
# Předpoklad: rclone s nastaveným vzdáleným úložištěm "izo" (rclone config), viz README, oddíl Hosting.
# Přístupové klíče jsou JEN v konfiguraci rclone na tomhle počítači (rclone config file), nikdy v repu.
# Token izomapa-zapis má mít práva Object Read & Write jen na bucket mapovna-izomapa.
set -e
cd "$(dirname "$0")"
REMOTE="${IZO_REMOTE:-izo}"          # název vzdáleného úložiště v rclone
BUCKET="${IZO_BUCKET:-mapovna-izomapa}"
[ -f site/index.html ] || { echo "site/index.html neexistuje, nejdřív ./postav.sh"; exit 1; }
command -v rclone >/dev/null 2>&1 || { echo "rclone není nainstalovaný (winget install Rclone.Rclone)"; exit 1; }
rclone listremotes | grep -qx "$REMOTE:" || { echo "rclone nemá vzdálené úložiště '$REMOTE' (rclone config)"; exit 1; }
DRY=""; [ "$1" = "-n" ] && DRY="--dry-run" && echo "ZKOUŠKA: nic se neodešle"

# rclone nastaví Content-Type podle přípony (.webp, .json, .html); R2 nezná výchozí index.html,
# ten řeší pravidlo Transform Rule v Cloudflare (viz README).
# Dlaždice a obrázky se mění jen při novém renderu, proto dlouhá cache; web a data kratší.
COMMON="--s3-no-check-bucket --checksum --transfers 32 --checkers 64 --fast-list --stats 10s --stats-one-line $DRY"
rclone sync site "$REMOTE:$BUCKET" $COMMON \
  --exclude "*.html" --exclude "*.json" --exclude "robots.txt" \
  --header-upload "Cache-Control: public, max-age=86400"
# (copy místo sync: zastaralé .json/.html na R2 se samy nemažou, stačí je jednou smazat ručně)
rclone copy site "$REMOTE:$BUCKET" $COMMON \
  --include "*.html" --include "*.json" --include "robots.txt" \
  --header-upload "Cache-Control: public, max-age=300"
echo "Hotovo. $( [ -n "$DRY" ] && echo '(zkouška)' ) Adresa: https://izo.mapovna.app/"
