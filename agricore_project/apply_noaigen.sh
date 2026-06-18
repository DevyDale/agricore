#!/usr/bin/env bash
# Remove external/AI image generation from the marketplace. Show the seller's uploaded
# product image (image_display) in the tile; plain gradient placeholder when none.
set -uo pipefail
if [ ! -f templates/marketplace.html ]; then echo "X Run from project root (needs templates/marketplace.html)."; exit 1; fi
BK="noaigen_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/marketplace.html "$BK/templates/marketplace.html"
echo ">> Backup: $BK/templates/marketplace.html"
cat > .na.py << 'NAW_PY_EOF'
import sys
PATH='templates/marketplace.html'
s=open(PATH,encoding='utf-8').read()
if 'class="aiimg"' not in s and 'pollinations' not in s:
    print('   - image generation already removed'); sys.exit(0)

OLD_PIMG = '''        function pimgInner(p, big){ const real=p.image_display||p.image||p.image_url; const base=genThumb(p,big); const oc=`onclick="openDetail(${p.id})"`; if(real){ return base + `<img ${oc} src="${escHtml(real)}" onerror="this.remove()" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover;cursor:pointer">`; } return base + `<img class="aiimg" ${oc} decoding="async" fetchpriority="high" alt="" src="${aiImgUrl(p)}" onload="this.style.opacity=1" onerror="this.remove()" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover;opacity:0;transition:opacity .45s ease;cursor:pointer">`; }'''
NEW_PIMG = '''        function pimgInner(p, big){ const real=p.image_display||p.image||p.image_url; const base=genThumb(p,big); const oc=`onclick="openDetail(${p.id})"`; if(real){ return base + `<img ${oc} src="${escHtml(real)}" onerror="this.remove()" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover;cursor:pointer">`; } return base; }'''

OLD_AIURL = '''        function aiImgUrl(p){ const prompt=(p.title||'farm product')+' '+(p.category||'')+', realistic product photo, plain background'; return 'https://image.pollinations.ai/prompt/'+encodeURIComponent(prompt)+'?width=256&height=256&nologo=true&model=turbo&seed='+encodeURIComponent(p.id||0); }'''

PRECONNECT = '''    <link rel="preconnect" href="https://image.pollinations.ai" crossorigin>'''

if OLD_PIMG not in s:
    print('   X pimgInner anchor not found -> untouched'); sys.exit(1)
s = s.replace(OLD_PIMG, NEW_PIMG, 1)
# remove the now-unused generator + preconnect (leave blank lines, harmless)
s = s.replace(OLD_AIURL, '', 1)
s = s.replace(PRECONNECT, '', 1)

open(PATH,'w',encoding='utf-8').write(s)
print('   OK marketplace now shows the uploaded image (no external generation)')
NAW_PY_EOF
python3 .na.py; RC=$?
rm -f .na.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/templates/marketplace.html templates/marketplace.html"; exit 1; fi
echo ">> Done. Hard-refresh marketplace.html. Rollback: cp -a $BK/templates/marketplace.html templates/marketplace.html"
