#!/usr/bin/env bash
# Fix 400 on product save: strip empty image/date from the digital_store Add/Edit form
# before sending, so edits (and adds without a new image) no longer fail.
set -uo pipefail
if [ ! -f templates/digital_store.html ]; then echo "X Run from project root (needs templates/digital_store.html)."; exit 1; fi
BK="prodfix_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/digital_store.html "$BK/templates/digital_store.html"
echo ">> Backup: $BK/templates/digital_store.html"
cat > .pf.py << 'PFW_PY_EOF'
import sys
PATH='templates/digital_store.html'
s=open(PATH,encoding='utf-8').read()
if "formData.delete('image')" in s:
    print('   - product save fix already applied'); sys.exit(0)

OLD = """                const formData = new FormData(form);

                const imageFile = document.getElementById('product-image').files[0];"""
NEW = """                const formData = new FormData(form);

                // Strip empty fields DRF rejects (empty file input, blank date) before sending
                formData.delete('image');
                formData.delete('image_url');
                if (!formData.get('expiration_date')) formData.delete('expiration_date');

                const imageFile = document.getElementById('product-image').files[0];"""

if OLD not in s:
    print('   X add/edit product FormData anchor not found -> untouched'); sys.exit(1)
s = s.replace(OLD, NEW, 1)
open(PATH,'w',encoding='utf-8').write(s)
print('   OK product save fix applied (no more 400 on empty image / date)')
PFW_PY_EOF
python3 .pf.py; RC=$?
rm -f .pf.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/templates/digital_store.html templates/digital_store.html"; exit 1; fi
echo ">> Done. Hard-refresh digital_store. Rollback: cp -a $BK/templates/digital_store.html templates/digital_store.html"
