#!/usr/bin/env bash
# Fix product image upload: convert iPhone HEIC/HEIF photos to JPEG in the browser
# before sending (Django/Pillow can't read HEIC -> 400). Also strips empty image/date
# fields so no-image edits save. Frontend-only; no pip install, no server restart needed.
set -uo pipefail
if [ ! -f templates/digital_store.html ]; then echo "X Run from project root (needs templates/digital_store.html)."; exit 1; fi
BK="heicfix_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/digital_store.html "$BK/templates/digital_store.html"
echo ">> Backup: $BK/templates/digital_store.html"
cat > .heic.py << 'HEICW_EOF'
import sys
PATH='templates/digital_store.html'
s=open(PATH,encoding='utf-8').read()

if 'heic2any' in s:
    print('   - HEIC fix already present'); sys.exit(0)

# ---- edit A: strip empty image/date from FormData (skip if already done by prodfix) ----
A_OLD = """                const formData = new FormData(form);

                const imageFile = document.getElementById('product-image').files[0];"""
A_NEW = """                const formData = new FormData(form);

                // Strip empty fields DRF rejects (empty file input, blank date) before sending
                formData.delete('image');
                formData.delete('image_url');
                if (!formData.get('expiration_date')) formData.delete('expiration_date');

                const imageFile = document.getElementById('product-image').files[0];"""
if "formData.delete('image')" not in s:
    if A_OLD not in s:
        print('   X FormData anchor not found -> untouched'); sys.exit(1)
    s = s.replace(A_OLD, A_NEW, 1)

# ---- edit B: convert HEIC/HEIF -> JPEG in-browser before upload ----
B_OLD = """                const imageFile = document.getElementById('product-image').files[0];
                const imageUrl = document.getElementById('product-image-url').value;

                if (imageFile) {
                    formData.append('image', imageFile);
                } else if (imageUrl) {
                    formData.append('image_url', imageUrl);
                }"""
B_NEW = r'''                const imageFile = document.getElementById('product-image').files[0];
                const imageUrl = document.getElementById('product-image-url').value;

                let uploadFile = imageFile;
                if (uploadFile && /\.(heic|heif)$/i.test(uploadFile.name || '')) {
                    try {
                        if (!window.heic2any) {
                            await new Promise((res, rej) => {
                                const sc = document.createElement('script');
                                sc.src = 'https://cdn.jsdelivr.net/npm/heic2any@0.0.4/dist/heic2any.min.js';
                                sc.onload = res; sc.onerror = () => rej(new Error('heic2any load failed'));
                                document.head.appendChild(sc);
                            });
                        }
                        const _out = await window.heic2any({ blob: uploadFile, toType: 'image/jpeg', quality: 0.85 });
                        const _jpeg = Array.isArray(_out) ? _out[0] : _out;
                        const _nm = (uploadFile.name || 'photo').replace(/\.(heic|heif)$/i, '.jpg');
                        uploadFile = new File([_jpeg], _nm, { type: 'image/jpeg' });
                    } catch (convErr) {
                        console.error('[HEIC] convert failed', convErr);
                        if (typeof errorDiv !== 'undefined' && errorDiv) errorDiv.textContent = 'Could not read that HEIC photo. Please upload a JPG or PNG instead.';
                        return;
                    }
                }

                if (uploadFile) {
                    formData.append('image', uploadFile);
                } else if (imageUrl) {
                    formData.append('image_url', imageUrl);
                }'''
if B_OLD not in s:
    print('   X image-upload anchor not found -> untouched'); sys.exit(1)
s = s.replace(B_OLD, B_NEW, 1)

open(PATH,'w',encoding='utf-8').write(s)
print('   OK HEIC->JPEG conversion + empty-field guard applied')
HEICW_EOF
python3 .heic.py; RC=$?
rm -f .heic.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/templates/digital_store.html templates/digital_store.html"; exit 1; fi
echo ">> Done. Hard-refresh digital_store, then re-pick the .heic file and Save."
echo ">> Rollback: cp -a $BK/templates/digital_store.html templates/digital_store.html"
