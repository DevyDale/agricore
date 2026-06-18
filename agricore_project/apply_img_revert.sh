#!/usr/bin/env bash
# Revert product images to Pollinations (works on your network), fast turbo model @256px.
set -uo pipefail
if [ ! -f templates/marketplace.html ]; then echo "X Run from project root (needs templates/marketplace.html)."; exit 1; fi
BK="imgrevert_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/marketplace.html "$BK/templates/marketplace.html"
echo ">> Backup: $BK/templates/marketplace.html"
cat > .ir.py << 'IRW_PY_EOF'
import sys, re
PATH='templates/marketplace.html'
s=open(PATH,encoding='utf-8').read()
if 'image.pollinations.ai' in s and 'width=256' in s:
    print('   - already on fast Pollinations (256/turbo)'); sys.exit(0)
if 'function aiImgUrl' not in s:
    print('   X aiImgUrl not found -> untouched'); sys.exit(1)

NEW = r'''        function aiImgUrl(p){ const prompt=(p.title||'farm product')+' '+(p.category||'')+', realistic product photo, plain background'; return 'https://image.pollinations.ai/prompt/'+encodeURIComponent(prompt)+'?width=256&height=256&nologo=true&model=turbo&seed='+encodeURIComponent(p.id||0); }'''

pat = re.compile(r'(?m)^[ \t]*function aiImgUrl\(p\)\{.*\}[ \t]*$')
s2, n = pat.subn(lambda m: NEW, s, count=1)
if n != 1:
    print('   X could not locate aiImgUrl one-liner -> untouched'); sys.exit(1)
# ensure preconnect points at pollinations (it may already)
if 'preconnect" href="https://image.pollinations.ai' not in s2:
    h=s2.find('</head>')
    if h>=0:
        s2=s2[:h]+'    <link rel="preconnect" href="https://image.pollinations.ai" crossorigin>\n'+s2[h:]
open(PATH,'w',encoding='utf-8').write(s2)
print('   OK reverted to Pollinations turbo @256px (works on your network; cached after first load)')
IRW_PY_EOF
python3 .ir.py; RC=$?
rm -f .ir.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/templates/marketplace.html templates/marketplace.html"; exit 1; fi
echo ">> Done. Hard-refresh marketplace.html. Rollback: cp -a $BK/templates/marketplace.html templates/marketplace.html"
