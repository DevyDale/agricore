#!/usr/bin/env bash
# Verified Trade Chain v1 (frontend): buyer sees their delivery code + a
# Report-a-problem button (marketplace.html); seller gets Dispatch -> Confirm
# delivery with the buyer's code (digital_store.html). Frontend only: no
# migration, no restart -- just hard-refresh the pages after running.
set -uo pipefail
if [ ! -f templates/marketplace.html ] || [ ! -f templates/digital_store.html ]; then
  echo "X Run from the Django project root (needs templates/marketplace.html and templates/digital_store.html)."; exit 1
fi
BK="tradeui_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
cp -a templates/marketplace.html "$BK/marketplace.html"
cp -a templates/digital_store.html "$BK/digital_store.html"
echo ">> Backup: $BK/"
cat > .tradeui.py << 'TRADEUI_EOF'
import sys

# ============================ marketplace.html (buyer) ============================
MP = 'templates/marketplace.html'
m = open(MP, encoding='utf-8').read()
if 'disputeEscrow' not in m:
    # A) extend the escrow action branches: dispute button + disputed state + OTP block
    A_OLD = """                else if(es==='held') action='<button class="addbtn" onclick="releaseEscrow('+esc.id+')"><i class="fas fa-box-open"></i> Confirm delivery &amp; release</button>';
                else if(es==='released') action='<span class="muted"><i class="fas fa-circle-check" style="color:#047857"></i> Completed</span>';
            }"""
    A_NEW = """                else if(es==='held') action='<button class="buybtn" onclick="releaseEscrow('+esc.id+')"><i class="fas fa-box-open"></i> Confirm &amp; release</button> <button class="buybtn" style="border-color:#fca5a5;color:#dc2626" onclick="disputeEscrow('+esc.id+')"><i class="fas fa-flag"></i> Report a problem</button>';
                else if(es==='released') action='<span class="muted"><i class="fas fa-circle-check" style="color:#047857"></i> Completed</span>';
                else if(es==='disputed') action='<span class="muted" style="color:#dc2626"><i class="fas fa-flag"></i> Reported \\u2014 under review</span>';
                if(es==='held' && esc.delivery_otp){ action = '<div style="margin-bottom:.5rem;padding:.55rem .75rem;background:#ecfdf5;border:1px solid #a7f3d0;border-radius:10px"><div style="font-size:.7rem;font-weight:700;color:#065f46;text-transform:uppercase;letter-spacing:.04em">Delivery code</div><div style="font-family:Fraunces,serif;font-size:1.5rem;font-weight:900;letter-spacing:.18em;color:#047857">'+escHtml(esc.delivery_otp)+'</div><div class="muted" style="font-size:.7rem">Give this to the courier only when your order arrives \\u2014 it confirms delivery.</div></div>' + action; }
            }"""
    if A_OLD not in m:
        print('   X marketplace renderOrderCard anchor not found -> untouched'); sys.exit(1)
    m = m.replace(A_OLD, A_NEW, 1)

    # B) add disputeEscrow() just before releaseEscrow()
    B_OLD = """        window.releaseEscrow=async function(escrowId){"""
    B_NEW = """        window.disputeEscrow=async function(escrowId){
            const reason=prompt('What went wrong? (e.g. wrong quantity, damaged, never arrived)');
            if(reason===null) return;
            try{ await apiPost('/escrows/'+escrowId+'/dispute/', { reason: reason||'' }); toast('Reported. Your payment stays frozen while we review.'); loadMyOrders(); }
            catch(e){ toast(e.message||'Could not open dispute.'); }
        };
        window.releaseEscrow=async function(escrowId){"""
    if B_OLD not in m:
        print('   X marketplace releaseEscrow anchor not found -> untouched'); sys.exit(1)
    m = m.replace(B_OLD, B_NEW, 1)
    open(MP, 'w', encoding='utf-8').write(m)
    print('   OK marketplace.html: buyer delivery code + Report-a-problem')
else:
    print('   - marketplace.html already patched')

# ============================ digital_store.html (seller) ========================
DS = 'templates/digital_store.html'
d = open(DS, encoding='utf-8').read()
if 'sellerEscrowBlock' not in d:
    # C) insert seller escrow helpers before renderIncomingOrders
    C_OLD = """        function renderIncomingOrders(list){"""
    C_NEW = """        function sellerEscrowBlock(o){
            const esc = (typeof escrowOf === 'function') ? escrowOf(o.id) : null;
            if (!esc) return '';
            const es = String(esc.status || '').toLowerCase();
            if (es === 'held' && !esc.otp_issued_at)
                return '<div class="mt-2"><button onclick="dispatchOrder(' + esc.id + ')" class="px-3 py-1.5 text-xs font-semibold bg-emerald-600 text-white rounded-lg hover:bg-emerald-700 transition"><i class="fas fa-truck"></i> Dispatch order</button></div>';
            if (es === 'held' && esc.otp_issued_at && !esc.delivered_confirmed_at)
                return '<div class="mt-2"><button onclick="confirmDeliveryPrompt(' + esc.id + ')" class="px-3 py-1.5 text-xs font-semibold bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition"><i class="fas fa-key"></i> Confirm delivery (enter buyer code)</button></div>';
            if (es === 'held' && esc.delivered_confirmed_at) {
                let when = ''; try { when = new Date(esc.dispute_deadline).toLocaleString(); } catch (e) {}
                return '<div class="mt-2 text-xs text-emerald-700"><i class="fas fa-clock"></i> Delivered \\u2014 you are paid automatically' + (when ? (' after ' + when) : '') + ' if no dispute.</div>';
            }
            if (es === 'disputed') return '<div class="mt-2 text-xs text-red-600"><i class="fas fa-flag"></i> Buyer reported a problem \\u2014 under review.</div>';
            if (es === 'released') return '<div class="mt-2 text-xs text-emerald-700"><i class="fas fa-circle-check"></i> Paid out.</div>';
            return '';
        }
        window.dispatchOrder = async function(escrowId){
            try {
                const r = await fetch(API_BASE + '/escrows/' + escrowId + '/issue_otp/', { method: 'POST', headers: { 'Authorization': 'Bearer ' + (token || '') } });
                if (!r.ok) { let msg = 'Could not dispatch.'; try { const j = await r.json(); msg = j.detail || msg; } catch (e) {} throw new Error(msg); }
                toast('Dispatched. The buyer now has a delivery code.', 'success');
                MKT.loaded = false; loadOrders();
            } catch (e) { toast(e.message || 'Could not dispatch.', 'error'); }
        };
        window.confirmDeliveryPrompt = async function(escrowId){
            const otp = prompt('Enter the delivery code the buyer gives you at hand-over:');
            if (otp === null) return;
            try {
                const r = await fetch(API_BASE + '/escrows/' + escrowId + '/confirm_delivery/', { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + (token || '') }, body: JSON.stringify({ otp: String(otp).trim() }) });
                if (!r.ok) { let msg = 'Could not confirm delivery.'; try { const j = await r.json(); msg = j.detail || msg; } catch (e) {} throw new Error(msg); }
                toast('Delivery confirmed. You will be paid after the dispute window.', 'success');
                MKT.loaded = false; loadOrders();
            } catch (e) { toast(e.message || 'Could not confirm delivery.', 'error'); }
        };

        function renderIncomingOrders(list){"""
    if C_OLD not in d:
        print('   X digital_store renderIncomingOrders anchor not found -> untouched'); sys.exit(1)
    d = d.replace(C_OLD, C_NEW, 1)

    # D) render the escrow block inside each incoming order card
    D_OLD = """                        + '<button onclick="cancelOrder(' + o.id + ')" class="px-3 py-1.5 text-xs font-semibold bg-white text-red-600 border border-red-100 rounded-lg hover:bg-red-50 transition">Cancel</button>'
                        + '</div>')
                    + '</div>';"""
    D_NEW = """                        + '<button onclick="cancelOrder(' + o.id + ')" class="px-3 py-1.5 text-xs font-semibold bg-white text-red-600 border border-red-100 rounded-lg hover:bg-red-50 transition">Cancel</button>'
                        + '</div>')
                    + sellerEscrowBlock(o)
                    + '</div>';"""
    if D_OLD not in d:
        print('   X digital_store incoming-card anchor not found -> untouched'); sys.exit(1)
    d = d.replace(D_OLD, D_NEW, 1)
    open(DS, 'w', encoding='utf-8').write(d)
    print('   OK digital_store.html: seller Dispatch + Confirm-delivery flow')
else:
    print('   - digital_store.html already patched')

print('DONE')
TRADEUI_EOF
python3 .tradeui.py; RC=$?
rm -f .tradeui.py
if [ $RC -ne 0 ]; then
  echo "X failed; restoring originals."
  cp -a "$BK/marketplace.html" templates/marketplace.html
  cp -a "$BK/digital_store.html" templates/digital_store.html
  exit 1
fi
echo ""
echo ">> Frontend applied. Hard-refresh (Cmd+Shift+R) marketplace.html and digital_store.html."
echo ">> Rollback: cp -a $BK/marketplace.html templates/marketplace.html && cp -a $BK/digital_store.html templates/digital_store.html"
