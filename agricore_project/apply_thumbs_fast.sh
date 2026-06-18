#!/usr/bin/env bash
# Faster auto-images: Pollinations turbo model @384px, eager-load + preconnect, name-aware fallback icons.
# Apply AFTER apply_thumbs.sh.
set -uo pipefail
if [ ! -f templates/marketplace.html ]; then echo "X Run from project root (needs templates/marketplace.html)."; exit 1; fi
BK="thumbsfast_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/marketplace.html "$BK/templates/marketplace.html"
echo ">> Backup: $BK/templates/marketplace.html"
cat > .tf.py << 'TFW_PY_EOF'
import sys
PATH='templates/marketplace.html'
s=open(PATH,encoding='utf-8').read()
if 'model=turbo' in s:
    print('   - fast image update already applied'); sys.exit(0)
if 'function aiImgUrl' not in s:
    print('   X aiImgUrl not found -> run apply_thumbs.sh first; untouched'); sys.exit(1)

OLD_AI = '''        function aiImgUrl(p){ const prompt=(p.title||'farm product')+', '+(p.category||'agriculture')+', professional product photo, white background, studio lighting, high detail'; return 'https://image.pollinations.ai/prompt/'+encodeURIComponent(prompt)+'?width=512&height=512&nologo=true&seed='+encodeURIComponent(p.id||0); }'''
NEW_AI = '''        function aiImgUrl(p){ const prompt=(p.title||'farm product')+' '+(p.category||'')+', realistic product photo, centered, plain background'; return 'https://image.pollinations.ai/prompt/'+encodeURIComponent(prompt)+'?width=384&height=384&nologo=true&model=turbo&seed='+encodeURIComponent(p.id||0); }'''

OLD_ICON = '''        function catIcon(c){ c=(c||'').toLowerCase(); if(c.indexOf('livestock')>-1||c.indexOf('animal')>-1) return 'fa-cow'; if(c.indexOf('crop')>-1||c.indexOf('produce')>-1||c.indexOf('grain')>-1) return 'fa-wheat-awn'; if(c.indexOf('machin')>-1||c.indexOf('equip')>-1) return 'fa-tractor'; if(c.indexOf('chemical')>-1||c.indexOf('input')>-1||c.indexOf('fertil')>-1) return 'fa-flask'; return 'fa-seedling'; }'''
NEW_ICON = '''        function catIcon(c){ c=(c||'').toLowerCase(); if(/beef|cattle|cow|goat|sheep|pork|pig|lamb|mutton|meat|livestock|poultry|chicken|egg|animal/.test(c)) return 'fa-cow'; if(/milk|dairy|yogurt|cheese|butter/.test(c)) return 'fa-bottle-droplet'; if(/tractor|machin|equip|tool|harvester|plough|plow/.test(c)) return 'fa-tractor'; if(/chemical|fertil|pesticide|herbicide|spray|input/.test(c)) return 'fa-flask'; if(/fruit|vegetable|tomato|mango|banana|apple|orange/.test(c)) return 'fa-apple-whole'; if(/maize|corn|grain|wheat|rice|cereal|sorghum|barley|millet|bean|sesame|simsim|seed|crop|produce/.test(c)) return 'fa-wheat-awn'; return 'fa-seedling'; }'''

OLD_CALL = '''catIcon(p.category)'''
NEW_CALL = '''catIcon((p.title||'')+' '+(p.category||''))'''

OLD_LAZY = '''class="aiimg" ${oc} loading="lazy"'''
NEW_LAZY = '''class="aiimg" ${oc} decoding="async" fetchpriority="high"'''

PRECONNECT = '''    <link rel="preconnect" href="https://image.pollinations.ai" crossorigin>
'''

for label,old,new in [('aiImgUrl',OLD_AI,NEW_AI),('catIcon',OLD_ICON,NEW_ICON),('genThumb call',OLD_CALL,NEW_CALL),('eager-load',OLD_LAZY,NEW_LAZY)]:
    if old not in s:
        print('   X anchor not found: '+label+' -> untouched'); sys.exit(1)
    s=s.replace(old,new,1)

h=s.find('</head>')
if h>=0 and 'preconnect" href="https://image.pollinations.ai' not in s:
    s=s[:h]+PRECONNECT+s[h:]

open(PATH,'w',encoding='utf-8').write(s)
print('   OK images now use fast turbo model (384px), eager-load, preconnect, name-aware icons')
TFW_PY_EOF
python3 .tf.py; RC=$?
rm -f .tf.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/templates/marketplace.html templates/marketplace.html"; exit 1; fi
echo ">> Done. Hard-refresh marketplace.html. Rollback: cp -a $BK/templates/marketplace.html templates/marketplace.html"
