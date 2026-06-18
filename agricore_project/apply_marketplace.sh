#!/usr/bin/env bash
# Agricore Marketplace — instant skeleton loader + cached catalog (faster paint)
# + Dale gets full-catalog & feature knowledge for purchase recommendations.
set -uo pipefail
if [ ! -f templates/marketplace.html ]; then echo "X Run from project root (needs templates/marketplace.html)."; exit 1; fi
BK="marketplace_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/marketplace.html "$BK/templates/marketplace.html"
echo ">> Backup: $BK/templates/marketplace.html"
cat > .mkt.py << 'MKT_PY_EOF'
import sys
PATH='templates/marketplace.html'
s=open(PATH,encoding='utf-8').read()
if '/* ---- product loading skeletons ---- */' in s:
    print('   - marketplace speed/Dale updates already applied'); sys.exit(0)

CSS = '''        /* ---- product loading skeletons ---- */
        .skel{ background:linear-gradient(90deg,#eef2ec 25%,#f6faf4 37%,#eef2ec 63%); background-size:400% 100%; animation:skelg 1.3s ease infinite; border-radius:8px }
        @keyframes skelg{ 0%{ background-position:100% 0 } 100%{ background-position:-100% 0 } }
        .skel-card{ background:#fff; border:1px solid var(--line); border-radius:18px; overflow:hidden }
        .skel-img{ height:190px; border-radius:0 }
        .skel-line{ height:12px; margin:.5rem 0 }
'''

OLD_LOAD = '''        async function load(){
            try{
                const res=await fetch(`${API}/products/`,{ headers:{'Authorization':'Bearer '+token} });
                if(res.status===401){ window.location.href='authentication.html'; return; }
                const data=await res.json(); products=Array.isArray(data)?data:(data.results||[]); render();
            }catch(e){ $('product-grid-all').innerHTML='<div style="grid-column:1/-1;text-align:center;padding:4rem;color:#dc2626">Failed to load products</div>'; }
        }'''

NEW_LOAD = '''        function skelCard(){ return '<div class="skel-card"><div class="skel skel-img"></div><div style="padding:1.1rem"><div class="skel skel-line" style="width:42%"></div><div class="skel skel-line" style="width:82%;height:18px"></div><div class="skel skel-line" style="width:100%"></div><div class="skel skel-line" style="width:64%"></div><div class="skel skel-line" style="width:55%;height:34px;margin-top:1rem"></div></div></div>'; }
        function showSkeletons(n){ const g=$('product-grid-all'); if(g) g.innerHTML=Array.from({length:n||per}).map(skelCard).join(''); }
        async function load(){
            let painted=false;
            try{ const c=sessionStorage.getItem('agricore_products'); if(c){ const cached=JSON.parse(c); if(Array.isArray(cached)&&cached.length){ products=cached; render(); painted=true; } } }catch(e){}
            if(!painted) showSkeletons(per);
            try{
                const res=await fetch(`${API}/products/`,{ headers:{'Authorization':'Bearer '+token} });
                if(res.status===401){ window.location.href='authentication.html'; return; }
                const data=await res.json(); const fresh=Array.isArray(data)?data:(data.results||[]);
                products=fresh; render();
                try{ sessionStorage.setItem('agricore_products', JSON.stringify(fresh)); }catch(e){}
            }catch(e){ if(!painted) $('product-grid-all').innerHTML='<div style="grid-column:1/-1;text-align:center;padding:4rem;color:#dc2626">Failed to load products</div>'; }
        }'''

OLD_CTX = '''        window.__daleCtx = function(){ const v=(window.__mkView||products).slice(0,15).map(p=>({title:p.title,price:p.price,category:p.category,rating:p.average_rating,stock:p.stock_quantity})); return { page:'Marketplace', type:'marketplace', extras:{ filters:filters, visible_count:(window.__mkView||products).length, products:v } }; };'''

NEW_CTX = '''        const MARKETPLACE_FEATURES = "Agricore Marketplace features: search and browse farm products; filter by category, price range and minimum rating, and sort by price or rating; open a product to read and write star reviews; add to cart and check out with escrow-protected payment (money is held safely and only released to the seller after the buyer confirms delivery, paid via Flutterwave); track purchases and release escrow under 'My Orders'; message a product's seller directly from its card; dropship any product into your own store to resell it; share a product into any chat; and view sponsored ads. All payments are escrow-protected.";
        window.__daleCtx = function(){
            const all=(window.__mkView||products);
            const list=all.slice(0,80).map(p=>({ title:p.title, price:p.price, category:p.category, rating:p.average_rating, reviews:p.reviews_count, stock:p.stock_quantity, unit:p.unit, store:p.store_name }));
            let cart=[]; try{ cart=Object.values(getCart()).map(i=>({ title:i.title, price:i.price, qty:i.qty })); }catch(e){}
            return { page:'Marketplace', type:'marketplace', features:MARKETPLACE_FEATURES, extras:{ filters:filters, total_products:products.length, visible_count:all.length, products:list, cart:cart } };
        };'''

i=s.find('</style>')
if i<0: print('   X no </style>'); sys.exit(1)
s=s[:i]+CSS+s[i:]
for label,old,new in [('load',OLD_LOAD,NEW_LOAD),('daleCtx',OLD_CTX,NEW_CTX)]:
    if old not in s: print('   X '+label+' anchor not found -> untouched'); sys.exit(1)
    s=s.replace(old,new,1)
open(PATH,'w',encoding='utf-8').write(s)
print('   OK marketplace updated (skeleton + cache + Dale knowledge)')
MKT_PY_EOF
python3 .mkt.py; RC=$?
rm -f .mkt.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/templates/marketplace.html templates/marketplace.html"; exit 1; fi
echo ">> Done. Hard-refresh marketplace.html. Rollback: cp -a $BK/templates/marketplace.html templates/marketplace.html"
