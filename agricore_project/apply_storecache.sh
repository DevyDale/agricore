#!/usr/bin/env bash
# Make My Digital Stores load instantly on repeat visits: paint last-seen stores from a
# session cache, then re-fetch in the background. Frontend-only; no install, no restart.
set -uo pipefail
if [ ! -f templates/digitalstores.html ]; then echo "X Run from project root (needs templates/digitalstores.html)."; exit 1; fi
BK="storecache_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/digitalstores.html "$BK/templates/digitalstores.html"
echo ">> Backup: $BK/templates/digitalstores.html"
cat > .sc.py << 'SCW_EOF'
import sys
PATH='templates/digitalstores.html'
s=open(PATH,encoding='utf-8').read()

if 'agricore_my_stores_html' in s:
    print('   - stores instant-cache already applied'); sys.exit(0)

# EDIT 1: paint cached grid HTML instantly at the top of refresh(), skip spinner if painted
E1_OLD = """        async function refresh(){
            $('storesLoading').classList.add('on');
            const stores=await fetchStores();"""
E1_NEW = """        async function refresh(){
            let __painted=false;
            try{ const __h=sessionStorage.getItem('agricore_my_stores_html'); if(__h){ $('storesGrid').innerHTML=__h; tiles=Array.from($('storesGrid').getElementsByClassName('store')); filter(); __painted=true; } }catch(e){}
            if(!__painted) $('storesLoading').classList.add('on');
            const stores=await fetchStores();"""

# EDIT 2: clear cache when the fresh result is empty (so stale tiles don't linger)
E2_OLD = """tiles=[]; return; }"""
E2_NEW = """try{ sessionStorage.removeItem('agricore_my_stores_html'); }catch(e){} tiles=[]; return; }"""

# EDIT 3: write the rendered grid HTML to cache after a successful render
E3_OLD = """            tiles=Array.from(grid.getElementsByClassName('store')); filter(); $('storesLoading').classList.remove('on');
        }"""
E3_NEW = """            tiles=Array.from(grid.getElementsByClassName('store')); filter(); $('storesLoading').classList.remove('on');
            try{ sessionStorage.setItem('agricore_my_stores_html', grid.innerHTML); }catch(e){}
        }"""

for label, old in [('refresh-start', E1_OLD), ('empty-return', E2_OLD), ('render-end', E3_OLD)]:
    if old not in s:
        print('   X anchor not found (%s) -> untouched' % label); sys.exit(1)

s = s.replace(E1_OLD, E1_NEW, 1)
s = s.replace(E2_OLD, E2_NEW, 1)
s = s.replace(E3_OLD, E3_NEW, 1)
open(PATH,'w',encoding='utf-8').write(s)
print('   OK stores instant-cache applied (paints last-seen stores immediately)')
SCW_EOF
python3 .sc.py; RC=$?
rm -f .sc.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/templates/digitalstores.html templates/digitalstores.html"; exit 1; fi
echo ">> Done. Hard-refresh the stores page; revisits will paint instantly."
echo ">> Rollback: cp -a $BK/templates/digitalstores.html templates/digitalstores.html"
