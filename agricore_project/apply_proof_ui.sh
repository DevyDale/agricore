#!/usr/bin/env bash
# Proof of condition (frontend): a small photo+quantity modal on the seller's
# Dispatch and the buyer's Report-a-problem. Frontend only: no migration, just
# hard-refresh afterwards.
set -uo pipefail
if [ ! -f templates/marketplace.html ] || [ ! -f templates/digital_store.html ]; then
  echo "X Run from the Django project root."; exit 1
fi
BK="proofui_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
cp -a templates/marketplace.html "$BK/marketplace.html"
cp -a templates/digital_store.html "$BK/digital_store.html"
echo ">> Backup: $BK/"
cat > .proofui.py << 'PROOFUIW_EOF'
import sys

MODAL = """        function proofModal(opts){
            opts = opts || {};
            return new Promise(function(resolve){
                var ov = document.createElement('div');
                ov.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;z-index:99999;padding:1rem';
                var box = document.createElement('div');
                box.style.cssText = 'background:#fff;border-radius:14px;max-width:380px;width:100%;padding:1.1rem 1.2rem;box-shadow:0 10px 40px rgba(0,0,0,.25);font-family:inherit';
                var html = '<div style="font-weight:800;font-size:1.05rem;margin-bottom:.3rem">' + (opts.title || 'Details') + '</div>';
                if (opts.intro) html += '<div style="font-size:.8rem;color:#6b7280;margin-bottom:.7rem">' + opts.intro + '</div>';
                if (opts.reasonLabel) html += '<label style="font-size:.78rem;font-weight:600;color:#374151">' + opts.reasonLabel + '</label><textarea id="pm_reason" rows="2" style="width:100%;box-sizing:border-box;border:1px solid #d1d5db;border-radius:8px;padding:.45rem;margin:.2rem 0 .6rem;font-size:.85rem"></textarea>';
                html += '<label style="font-size:.78rem;font-weight:600;color:#374151">' + (opts.quantityLabel || 'Quantity / weight') + '</label><input id="pm_qty" type="text" placeholder="e.g. 10 sacks (~500kg)" style="width:100%;box-sizing:border-box;border:1px solid #d1d5db;border-radius:8px;padding:.45rem;margin:.2rem 0 .6rem;font-size:.85rem">';
                html += '<label style="font-size:.78rem;font-weight:600;color:#374151">Photo (optional)</label><input id="pm_photo" type="file" accept="image/*" style="width:100%;margin:.2rem 0 .9rem;font-size:.8rem">';
                html += '<div style="display:flex;gap:.5rem;justify-content:flex-end"><button id="pm_cancel" type="button" style="padding:.45rem .8rem;border:1px solid #d1d5db;background:#fff;border-radius:8px;font-size:.82rem;font-weight:600;cursor:pointer">Cancel</button><button id="pm_ok" type="button" style="padding:.45rem .9rem;border:none;background:#10b981;color:#fff;border-radius:8px;font-size:.82rem;font-weight:700;cursor:pointer">' + (opts.submitLabel || 'Submit') + '</button></div>';
                box.innerHTML = html;
                ov.appendChild(box);
                document.body.appendChild(ov);
                function close(v){ try { document.body.removeChild(ov); } catch (e) {} resolve(v); }
                box.querySelector('#pm_cancel').onclick = function(){ close(null); };
                ov.onclick = function(e){ if (e.target === ov) close(null); };
                box.querySelector('#pm_ok').onclick = function(){
                    var qEl = box.querySelector('#pm_qty');
                    var rEl = box.querySelector('#pm_reason');
                    var fEl = box.querySelector('#pm_photo');
                    var file = (fEl && fEl.files && fEl.files[0]) ? fEl.files[0] : null;
                    close({ qty: (qEl ? qEl.value : '').trim(), reason: (rEl ? rEl.value : '').trim(), file: file });
                };
            });
        }
"""

# ---- digital_store.html (seller dispatch) ----
DS='templates/digital_store.html'; d=open(DS,encoding='utf-8').read()
if 'function proofModal' not in d:
    DS_OLD='''        window.dispatchOrder = async function(escrowId){
            try {
                const r = await fetch(API_BASE + '/escrows/' + escrowId + '/issue_otp/', { method: 'POST', headers: { 'Authorization': 'Bearer ' + (token || '') } });
                if (!r.ok) { let msg = 'Could not dispatch.'; try { const j = await r.json(); msg = j.detail || msg; } catch (e) {} throw new Error(msg); }
                toast('Dispatched. The buyer now has a delivery code.', 'success');
                MKT.loaded = false; loadOrders();
            } catch (e) { toast(e.message || 'Could not dispatch.', 'error'); }
        };'''
    DS_NEW=MODAL + '''        window.dispatchOrder = async function(escrowId){
            const res = await proofModal({ title: 'Dispatch order', intro: 'Record what you are sending. A photo and weight protect you if the buyer disputes later.', quantityLabel: 'Quantity / weight sent', submitLabel: 'Dispatch' });
            if (res === null) return;
            const fd = new FormData();
            if (res.qty) fd.append('dispatch_quantity', res.qty);
            if (res.file) fd.append('dispatch_photo', res.file);
            try {
                const r = await fetch(API_BASE + '/escrows/' + escrowId + '/issue_otp/', { method: 'POST', headers: { 'Authorization': 'Bearer ' + (token || '') }, body: fd });
                if (!r.ok) { let msg = 'Could not dispatch.'; try { const j = await r.json(); msg = j.detail || msg; } catch (e) {} throw new Error(msg); }
                toast('Dispatched. The buyer now has a delivery code.', 'success');
                MKT.loaded = false; loadOrders();
            } catch (e) { toast(e.message || 'Could not dispatch.', 'error'); }
        };'''
    if DS_OLD not in d: print('   X digital_store dispatchOrder anchor not found'); sys.exit(1)
    open(DS,'w',encoding='utf-8').write(d.replace(DS_OLD,DS_NEW,1))
    print('   OK digital_store.html: dispatch modal (photo + weight)')
else: print('   - digital_store.html already patched')

# ---- marketplace.html (buyer dispute) ----
MP='templates/marketplace.html'; m=open(MP,encoding='utf-8').read()
if 'function proofModal' not in m:
    MP_OLD='''        window.disputeEscrow=async function(escrowId){
            const reason=prompt('What went wrong? (e.g. wrong quantity, damaged, never arrived)');
            if(reason===null) return;
            try{ await apiPost('/escrows/'+escrowId+'/dispute/', { reason: reason||'' }); toast('Reported. Your payment stays frozen while we review.'); loadMyOrders(); }
            catch(e){ toast(e.message||'Could not open dispute.'); }
        };'''
    MP_NEW=MODAL + '''        window.disputeEscrow=async function(escrowId){
            const res = await proofModal({ title: 'Report a problem', intro: 'Tell us what went wrong. A photo and the amount you actually received help us resolve it fairly.', reasonLabel: 'What went wrong?', quantityLabel: 'Amount you received (optional)', submitLabel: 'Submit report' });
            if (res === null) return;
            const fd = new FormData();
            fd.append('reason', res.reason || '');
            if (res.qty) fd.append('dispute_quantity', res.qty);
            if (res.file) fd.append('dispute_photo', res.file);
            try {
                const r = await fetch(API_BASE + '/escrows/' + escrowId + '/dispute/', { method: 'POST', headers: { 'Authorization': 'Bearer ' + (token || '') }, body: fd });
                if (!r.ok) { let msg = 'Could not open dispute.'; try { const j = await r.json(); msg = j.detail || msg; } catch (e) {} throw new Error(msg); }
                toast('Reported. Your payment stays frozen while we review.');
                loadMyOrders();
            } catch (e) { toast(e.message || 'Could not open dispute.'); }
        };'''
    if MP_OLD not in m: print('   X marketplace disputeEscrow anchor not found'); sys.exit(1)
    open(MP,'w',encoding='utf-8').write(m.replace(MP_OLD,MP_NEW,1))
    print('   OK marketplace.html: dispute modal (photo + received qty)')
else: print('   - marketplace.html already patched')
print('DONE')
PROOFUIW_EOF
python3 .proofui.py; RC=$?
rm -f .proofui.py
if [ $RC -ne 0 ]; then
  echo "X failed; restoring."
  cp -a "$BK/marketplace.html" templates/marketplace.html
  cp -a "$BK/digital_store.html" templates/digital_store.html
  exit 1
fi
echo ""
echo ">> Frontend applied. Hard-refresh (Cmd+Shift+R) both pages."
echo ">> Rollback: cp -a $BK/marketplace.html templates/marketplace.html && cp -a $BK/digital_store.html templates/digital_store.html"
