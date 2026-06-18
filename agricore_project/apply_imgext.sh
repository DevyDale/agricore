#!/usr/bin/env bash
# Product image: validate file extension and show the allowed formats (JPG/JPEG/PNG/WEBP/GIF)
# instead of trying to auto-convert HEIC. Frontend-only; no install, no server restart.
set -uo pipefail
if [ ! -f templates/digital_store.html ]; then echo "X Run from project root (needs templates/digital_store.html)."; exit 1; fi
BK="imgext_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/digital_store.html "$BK/templates/digital_store.html"
echo ">> Backup: $BK/templates/digital_store.html"
cat > .imgext.py << 'IMGEXTW_EOF'
import sys
PATH='templates/digital_store.html'
s=open(PATH,encoding='utf-8').read()

if 'ALLOWED_IMAGE_EXT' in s:
    print('   - image-format validation already applied'); sys.exit(0)

# ---- edit A: replace the HEIC-conversion submit block with extension validation ----
SUBMIT_OLD = r'''                const imageFile = document.getElementById('product-image').files[0];
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

SUBMIT_NEW = r'''                const imageFile = document.getElementById('product-image').files[0];
                const imageUrl = document.getElementById('product-image-url').value;

                const ALLOWED_IMAGE_EXT = ['jpg', 'jpeg', 'png', 'webp', 'gif'];
                if (imageFile) {
                    const ext = (imageFile.name.split('.').pop() || '').toLowerCase();
                    if (ALLOWED_IMAGE_EXT.indexOf(ext) === -1) {
                        errorDiv.textContent = 'Unsupported image type (.' + ext + '). Allowed formats: JPG, JPEG, PNG, WEBP, GIF. iPhone photos are usually .HEIC \u2014 set Camera to "Most Compatible" or upload a screenshot.';
                        errorDiv.classList.remove('hidden');
                        return;
                    }
                    formData.append('image', imageFile);
                } else if (imageUrl) {
                    formData.append('image_url', imageUrl);
                }'''

if SUBMIT_OLD not in s:
    print('   X submit-block anchor not found -> untouched'); sys.exit(1)
s = s.replace(SUBMIT_OLD, SUBMIT_NEW, 1)

# ---- edit B: validate on file selection (immediate feedback + clear the bad file) ----
CHANGE_OLD = r'''        document.getElementById('product-image')?.addEventListener('change', (e) => {
            const file = e.target.files[0];
            if (file) {
                const reader = new FileReader();'''

CHANGE_NEW = r'''        document.getElementById('product-image')?.addEventListener('change', (e) => {
            const file = e.target.files[0];
            if (file) {
                const _ext = (file.name.split('.').pop() || '').toLowerCase();
                if (['jpg', 'jpeg', 'png', 'webp', 'gif'].indexOf(_ext) === -1) {
                    const _err = document.getElementById('add-product-error');
                    if (_err) { _err.textContent = 'Unsupported image type (.' + _ext + '). Allowed formats: JPG, JPEG, PNG, WEBP, GIF.'; _err.classList.remove('hidden'); }
                    e.target.value = '';
                    document.getElementById('image-preview').classList.add('hidden');
                    return;
                }
                const reader = new FileReader();'''

if CHANGE_OLD not in s:
    print('   X file-picker anchor not found -> untouched'); sys.exit(1)
s = s.replace(CHANGE_OLD, CHANGE_NEW, 1)

open(PATH,'w',encoding='utf-8').write(s)
print('   OK image-format validation applied (allowed: JPG, JPEG, PNG, WEBP, GIF)')
IMGEXTW_EOF
python3 .imgext.py; RC=$?
rm -f .imgext.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/templates/digital_store.html templates/digital_store.html"; exit 1; fi
echo ">> Done. Hard-refresh digital_store. Allowed image types: JPG, JPEG, PNG, WEBP, GIF."
echo ">> Rollback: cp -a $BK/templates/digital_store.html templates/digital_store.html"
