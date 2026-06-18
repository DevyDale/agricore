#!/usr/bin/env bash
# Swap on-demand AI image generation for fast keyword-matched photos (LoremFlickr).
# Thumbnail still shows instantly + stays as fallback. Apply AFTER apply_thumbs.sh.
set -uo pipefail
if [ ! -f templates/marketplace.html ]; then echo "X Run from project root (needs templates/marketplace.html)."; exit 1; fi
BK="fastimg_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/marketplace.html "$BK/templates/marketplace.html"
echo ">> Backup: $BK/templates/marketplace.html"
cat > .fi.py << 'FIW_PY_EOF'
import sys, re
PATH='templates/marketplace.html'
s=open(PATH,encoding='utf-8').read()
if 'loremflickr.com' in s:
    print('   - fast image source already applied'); sys.exit(0)
if 'function aiImgUrl' not in s:
    print('   X aiImgUrl not found -> run apply_thumbs.sh first; untouched'); sys.exit(1)

NEW = r'''        function aiImgUrl(p){ const kw=encodeURIComponent(((p.title||'farm produce')+' '+(p.category||'')).trim().split(/\s+/).slice(0,3).join(',')); return 'https://loremflickr.com/400/400/'+kw+'?lock='+encodeURIComponent(p.id||0); }'''

pat = re.compile(r'(?m)^[ \t]*function aiImgUrl\(p\)\{.*\}[ \t]*$')
s2, n = pat.subn(lambda m: NEW, s, count=1)
if n != 1:
    print('   X could not locate the aiImgUrl one-liner -> untouched'); sys.exit(1)
open(PATH,'w',encoding='utf-8').write(s2)
print('   OK product images now load from a fast keyword photo source (no AI generation wait)')
FIW_PY_EOF
python3 .fi.py; RC=$?
rm -f .fi.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/templates/marketplace.html templates/marketplace.html"; exit 1; fi
echo ">> Done. Hard-refresh marketplace.html. Rollback: cp -a $BK/templates/marketplace.html templates/marketplace.html"
