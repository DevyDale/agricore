#!/usr/bin/env bash
# Product images: instant gradient+icon thumbnail from the product name,
# with a free keyless AI photo (Pollinations) fading in when ready. Real uploads still win.
set -uo pipefail
if [ ! -f templates/marketplace.html ]; then echo "X Run from project root (needs templates/marketplace.html)."; exit 1; fi
BK="thumbs_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/marketplace.html "$BK/templates/marketplace.html"
echo ">> Backup: $BK/templates/marketplace.html"
cat > .thumb.py << 'THUMBW_PY_EOF'
import sys
PATH='templates/marketplace.html'
s=open(PATH,encoding='utf-8').read()
if 'function pimgInner' in s:
    print('   - auto thumbnails already applied'); sys.exit(0)
if 'id="detail-modal"' not in s and 'function card(p)' not in s:
    print('   X does not look like marketplace.html -> untouched'); sys.exit(1)

CSS = '''        /* ---- auto product thumbnails ---- */
        .genthumb{ position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:.55rem; text-align:center; padding:1rem; color:#fff }
        .genthumb i{ font-size:3rem; filter:drop-shadow(0 3px 8px rgba(0,0,0,.22)); opacity:.97 }
        .genthumb .gt-name{ font-family:Fraunces,serif; font-weight:700; font-size:1.02rem; line-height:1.15; text-shadow:0 1px 5px rgba(0,0,0,.28); display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden }
        .genthumb.big i{ font-size:4.6rem }
        .genthumb.big .gt-name{ font-size:1.5rem; -webkit-line-clamp:3 }
        .detail-hero{ position:relative }
'''

HELPERS = '''        /* auto product thumbnails: instant gradient+icon, AI photo swaps in when ready */
        function prodHue(s){ s=String(s||''); let h=0; for(let i=0;i<s.length;i++){ h=(h*31 + s.charCodeAt(i))>>>0; } return h%360; }
        function catIcon(c){ c=(c||'').toLowerCase(); if(c.indexOf('livestock')>-1||c.indexOf('animal')>-1) return 'fa-cow'; if(c.indexOf('crop')>-1||c.indexOf('produce')>-1||c.indexOf('grain')>-1) return 'fa-wheat-awn'; if(c.indexOf('machin')>-1||c.indexOf('equip')>-1) return 'fa-tractor'; if(c.indexOf('chemical')>-1||c.indexOf('input')>-1||c.indexOf('fertil')>-1) return 'fa-flask'; return 'fa-seedling'; }
        function aiImgUrl(p){ const prompt=(p.title||'farm product')+', '+(p.category||'agriculture')+', professional product photo, white background, studio lighting, high detail'; return 'https://image.pollinations.ai/prompt/'+encodeURIComponent(prompt)+'?width=512&height=512&nologo=true&seed='+encodeURIComponent(p.id||0); }
        function genThumb(p, big){ const h=prodHue(p.title), h2=(h+38)%360; const icon=catIcon(p.category), t=escHtml(p.title||'Product'); return `<div class="genthumb${big?' big':''}" style="background:linear-gradient(135deg,hsl(${h},48%,44%),hsl(${h2},52%,30%))"><i class="fas ${icon}"></i><span class="gt-name">${t}</span></div>`; }
        function pimgInner(p, big){ const real=p.image_display||p.image||p.image_url; const base=genThumb(p,big); const oc=`onclick="openDetail(${p.id})"`; if(real){ return base + `<img ${oc} src="${escHtml(real)}" onerror="this.remove()" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover;cursor:pointer">`; } return base + `<img class="aiimg" ${oc} loading="lazy" alt="" src="${aiImgUrl(p)}" onload="this.style.opacity=1" onerror="this.remove()" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover;opacity:0;transition:opacity .45s ease;cursor:pointer">`; }
'''

EXPR = '''${img?`<img src="${img}" onclick="openDetail(${p.id})" style="cursor:pointer" onerror="this.style.display='none';this.nextElementSibling.style.display='grid'"><div class="ini" style="display:none;cursor:pointer" onclick="openDetail(${p.id})">${initials(p.title)}</div>`:`<div class="ini" style="cursor:pointer" onclick="openDetail(${p.id})">${initials(p.title)}</div>`}'''

# 1) CSS
i=s.find('</style>')
if i<0: print('   X no </style>'); sys.exit(1)
s=s[:i]+CSS+s[i:]
# 2) helpers before card()
anchor='        function card(p){'
if anchor not in s: print('   X card() anchor not found'); sys.exit(1)
s=s.replace(anchor, HELPERS+anchor, 1)
# 3) card image expression
if EXPR not in s: print('   X card image expression not found -> untouched'); sys.exit(1)
s=s.replace(EXPR, '${pimgInner(p)}', 1)
# 4) detail hero (line-based, indentation-preserving, no fragile escaping)
lines=s.split(chr(10)); done=False
for idx,ln in enumerate(lines):
    if "$('detail-hero').innerHTML = img?" in ln:
        ind=ln[:len(ln)-len(ln.lstrip())]
        lines[idx]=ind+"$('detail-hero').innerHTML = pimgInner(p, true);"
        done=True; break
if not done: print('   X detail-hero line not found -> untouched'); sys.exit(1)
s=chr(10).join(lines)

open(PATH,'w',encoding='utf-8').write(s)
print('   OK auto thumbnails + AI-photo swap wired into product cards and detail view')
THUMBW_PY_EOF
python3 .thumb.py; RC=$?
rm -f .thumb.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/templates/marketplace.html templates/marketplace.html"; exit 1; fi
echo ">> Done. Hard-refresh marketplace.html. Rollback: cp -a $BK/templates/marketplace.html templates/marketplace.html"
