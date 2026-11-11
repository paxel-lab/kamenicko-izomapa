"""Plakát pro veřejný web map: z build/nahled_summer.png vyrobí site/plakat-<šířka>.webp.

    python nastroje/plakat.py                    # 1200, 1600 a 2400 px, kvalita 70
    python nastroje/plakat.py VSTUP.png VYSTUP_DIR   # jiné umístění (např. při zkoušce)

Cílové velikosti: cca 60 / 120 / 280 kB. Spouští se po ./postav.sh a před ./nahrat.sh.
Soubory plakat-*.webp build_html.py ani postav.sh nemažou (postav.sh maže jen site/tiles).
"""
import os
import sys

from PIL import Image

Image.MAX_IMAGE_PIXELS = None
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIRKY = (1200, 1600, 2400)
KVALITA = 70


def main():
    vstup = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'build', 'nahled_summer.png')
    vystup = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'site')
    if not os.path.exists(vstup):
        sys.exit(f'Chybí {vstup}, nejdřív ./postav.sh a python compose.py summer 8')
    os.makedirs(vystup, exist_ok=True)
    im = Image.open(vstup).convert('RGB')
    for w in SIRKY:
        h = round(im.height * w / im.width)
        out = os.path.join(vystup, f'plakat-{w}.webp')
        im.resize((w, h), Image.LANCZOS).save(out, 'WEBP', quality=KVALITA, method=6)
        print(f'{out}: {w}x{h}, {os.path.getsize(out) / 1024:.0f} kB')


if __name__ == '__main__':
    main()
