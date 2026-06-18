#!/usr/bin/env bash
# Phase 2 (option a): delivery fee comes OUT OF SELLER PROCEEDS.
# On release the escrow splits: platform commission off the top, rider gets the
# job fee (if they delivered AND have a payout account), seller gets the rest.
# Buyer checkout is unchanged. Backend split + rider payout form. No migration.
set -uo pipefail
if [ ! -f escrow/api/views.py ] || [ ! -f templates/transporter.html ] || [ ! -f manage.py ]; then
  echo "X Run from the Django project root."; exit 1
fi
BK="feesplit_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
cp -a escrow/api/views.py "$BK/views.py"
cp -a templates/transporter.html "$BK/transporter.html"
echo ">> Backup: $BK/"
cat > .fs.py << 'FSW_EOF'
import sys, ast

# ===================== BACKEND: split payout =====================
VP='escrow/api/views.py'; v=open(VP,encoding='utf-8').read()
if 'riderpay' not in v:
    OLD = '''def initiate_seller_payout(escrow):
    """Create a payout transaction and ask Flutterwave to pay the seller.
    Returns (http_status, body). Shared by the buyer 'release' action and the
    automatic-release sweep so both behave identically."""
    if escrow.status != "held":
        return status.HTTP_400_BAD_REQUEST, {"detail": f"Cannot release from status: {escrow.status}."}
    if escrow.transactions.filter(kind="payout", status__in=["pending", "successful"]).exists():
        return status.HTTP_400_BAD_REQUEST, {"detail": "A payout for this escrow is already in progress."}
    seller = escrow.order.store.owner
    payout_account = getattr(seller, "payout_account", None)
    if payout_account is None:
        return status.HTTP_409_CONFLICT, {"detail": "The seller has not set up a payout account yet."}
    tx_ref = flutterwave.new_tx_ref(f"pay{escrow.pk}")
    txn = PaymentTransaction.objects.create(
        escrow=escrow, kind="payout", tx_ref=tx_ref,
        amount=escrow.amount, fee=0, currency=escrow.currency,
    )
    try:
        resp = flutterwave.initiate_transfer(
            amount=float(escrow.amount), currency=escrow.currency,
            account_bank=payout_account.account_bank,
            account_number=payout_account.account_number,
            beneficiary_name=payout_account.account_name,
            reference=tx_ref, narration=f"Agricore order #{escrow.order_id}",
        )
    except flutterwave.FlutterwaveError as e:
        txn.status = "failed"
        txn.raw = {"error": str(e)}
        txn.save()
        return status.HTTP_502_BAD_GATEWAY, {"detail": f"Could not start payout: {e}"}
    txn.flw_id = str((resp.get("data") or {}).get("id") or "")
    txn.raw = resp
    txn.save()
    return status.HTTP_200_OK, {
        "detail": "Payout initiated. The escrow will show 'released' once it completes.",
        "transfer_status": (resp.get("data") or {}).get("status"),
        "tx_ref": tx_ref,
    }'''

    NEW = '''def initiate_seller_payout(escrow):
    """Split-settle a held escrow: pay the assigned rider their delivery fee (out of
    the sale proceeds), pay the seller the remainder, keep the platform commission.
    Each leg is a separate Flutterwave transfer. Shared by the buyer 'release' action
    and the auto-release sweep. Returns (http_status, body)."""
    from decimal import Decimal, ROUND_HALF_UP
    cents = Decimal("0.01")

    def q(x):
        return Decimal(x).quantize(cents, rounding=ROUND_HALF_UP)

    if escrow.status != "held":
        return status.HTTP_400_BAD_REQUEST, {"detail": f"Cannot release from status: {escrow.status}."}
    if escrow.transactions.filter(kind="payout", status__in=["pending", "successful"]).exists():
        return status.HTTP_400_BAD_REQUEST, {"detail": "A payout for this escrow is already in progress."}

    seller = escrow.order.store.owner
    seller_acct = getattr(seller, "payout_account", None)
    if seller_acct is None:
        return status.HTTP_409_CONFLICT, {"detail": "The seller has not set up a payout account yet."}

    amount = q(escrow.amount)
    rate = Decimal(str(getattr(settings, "ESCROW_PLATFORM_COMMISSION_RATE", 0) or 0))
    commission = q(amount * rate)
    if commission < Decimal("0"):
        commission = q("0")

    # Rider fee, only if a rider did the delivery and can be paid.
    rider_fee = q("0")
    rider_acct = None
    job = None
    try:
        job = escrow.order.delivery_job
    except Exception:
        job = None
    if job is not None and job.transporter_id and job.status in ("picked_up", "delivered"):
        rider_acct = getattr(job.transporter.user, "payout_account", None)
        if rider_acct is not None and job.offered_fee:
            rider_fee = q(job.offered_fee)
    max_fee = amount - commission
    if rider_fee > max_fee:
        rider_fee = max_fee if max_fee > Decimal("0") else q("0")

    # Rider leg first: if it cannot even be initiated, give the fee back to the seller.
    if rider_fee > Decimal("0") and rider_acct is not None:
        rider_ref = flutterwave.new_tx_ref(f"riderpay{escrow.pk}")
        rider_txn = PaymentTransaction.objects.create(
            escrow=escrow, kind="payout", tx_ref=rider_ref,
            amount=rider_fee, fee=0, currency=escrow.currency,
        )
        try:
            rresp = flutterwave.initiate_transfer(
                amount=float(rider_fee), currency=escrow.currency,
                account_bank=rider_acct.account_bank,
                account_number=rider_acct.account_number,
                beneficiary_name=rider_acct.account_name,
                reference=rider_ref, narration=f"Agricore delivery #{escrow.order_id}",
            )
            rider_txn.flw_id = str((rresp.get("data") or {}).get("id") or "")
            rider_txn.raw = rresp
            rider_txn.save()
        except flutterwave.FlutterwaveError as e:
            rider_txn.status = "failed"
            rider_txn.raw = {"error": str(e)}
            rider_txn.save()
            rider_fee = q("0")

    seller_amount = amount - commission - rider_fee
    if seller_amount < Decimal("0"):
        seller_amount = q("0")
    seller_amount = q(seller_amount)

    seller_ref = flutterwave.new_tx_ref(f"pay{escrow.pk}")
    seller_txn = PaymentTransaction.objects.create(
        escrow=escrow, kind="payout", tx_ref=seller_ref,
        amount=seller_amount, fee=commission, currency=escrow.currency,
    )
    try:
        resp = flutterwave.initiate_transfer(
            amount=float(seller_amount), currency=escrow.currency,
            account_bank=seller_acct.account_bank,
            account_number=seller_acct.account_number,
            beneficiary_name=seller_acct.account_name,
            reference=seller_ref, narration=f"Agricore order #{escrow.order_id}",
        )
    except flutterwave.FlutterwaveError as e:
        seller_txn.status = "failed"
        seller_txn.raw = {"error": str(e)}
        seller_txn.save()
        return status.HTTP_502_BAD_GATEWAY, {"detail": f"Could not start payout: {e}"}
    seller_txn.flw_id = str((resp.get("data") or {}).get("id") or "")
    seller_txn.raw = resp
    seller_txn.save()
    return status.HTTP_200_OK, {
        "detail": "Payout initiated. The escrow will show 'released' once it completes.",
        "transfer_status": (resp.get("data") or {}).get("status"),
        "tx_ref": seller_ref,
        "seller_amount": str(seller_amount),
        "rider_fee": str(rider_fee),
        "commission": str(commission),
    }'''

    if OLD not in v: print('   X initiate_seller_payout anchor not found'); sys.exit(1)
    v = v.replace(OLD, NEW, 1)
    try: ast.parse(v)
    except SyntaxError as e: print('   X escrow views invalid:', e); sys.exit(1)
    open(VP,'w',encoding='utf-8').write(v)
    print('   OK escrow/api/views.py: split payout (seller + rider + commission)')
else:
    print('   - escrow views already split-aware')

# ===================== FRONTEND: rider payout form =====================
HP='templates/transporter.html'; h=open(HP,encoding='utf-8').read()
if 'renderPayout' not in h:
    h = h.replace('  let myProfile = null;', '  let myProfile = null;\n  let myPayout = null;', 1)
    h = h.replace(
        "      myProfile = await api('/transporters/me/');\n      renderProfile();",
        "      myProfile = await api('/transporters/me/');\n      try { const _pa = await api('/payout-accounts/'); const _l = listOf(_pa); myPayout = _l[0] || null; } catch (e) { myPayout = null; }\n      renderProfile();",
        1)
    h = h.replace(
        "      + (p.is_verified ? '' : '<p class=\"text-xs text-gray-400 mt-3\">Unverified riders can only accept lower-value orders until an admin verifies you.</p>');\n  }",
        "      + (p.is_verified ? '' : '<p class=\"text-xs text-gray-400 mt-3\">Unverified riders can only accept lower-value orders until an admin verifies you.</p>')\n      + '<div id=\"payout-card\" class=\"mt-4 pt-4 border-t border-gray-100\"></div>';\n    renderPayout();\n  }",
        1)
    INJECT = '''  function renderPayout() {
    const el = document.getElementById('payout-card'); if (!el) return;
    if (myPayout && myPayout.account_number) {
      el.innerHTML = '<div class="flex items-center justify-between gap-2">'
        + '<div><p class="text-sm font-semibold text-gray-800"><i class="fas fa-wallet text-emerald-600"></i> Payout</p>'
        + '<p class="text-xs text-gray-500">' + esc(myPayout.method) + ' \\u2022 ' + esc(myPayout.account_number) + ' \\u2022 ' + esc(myPayout.account_name) + '</p></div>'
        + '<button onclick="editPayout()" class="text-xs font-semibold text-emerald-700 underline">Change</button></div>';
    } else {
      payoutForm(el);
    }
  }
  window.editPayout = function () { const el = document.getElementById('payout-card'); if (el) payoutForm(el); };
  function payoutForm(el) {
    el.innerHTML =
      '<p class="text-sm font-semibold text-gray-800 mb-2"><i class="fas fa-wallet text-emerald-600"></i> Where you get paid</p>'
      + '<div class="grid grid-cols-1 sm:grid-cols-2 gap-2">'
      + '<select id="po_method" class="inp2"><option value="momo">Mobile Money</option><option value="bank">Bank</option></select>'
      + '<input id="po_num" class="inp2" placeholder="0772\\u2026 (MoMo) or account no.">'
      + '<input id="po_name" class="inp2" placeholder="Account holder name">'
      + '<input id="po_net" class="inp2" placeholder="Network (MTN / AIRTEL)">'
      + '<input id="po_bank" class="inp2" placeholder="Bank code (bank only)">'
      + '</div>'
      + '<button onclick="savePayout()" class="mt-2 px-3 py-1.5 bg-emerald-600 text-white rounded-lg text-xs font-semibold hover:bg-emerald-700">Save payout details</button>';
    document.querySelectorAll('.inp2').forEach(function (x) { x.className = 'inp2 w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-emerald-500 focus:outline-none'; });
    if (myPayout) {
      if (myPayout.method) document.getElementById('po_method').value = myPayout.method;
      document.getElementById('po_num').value = myPayout.account_number || '';
      document.getElementById('po_name').value = myPayout.account_name || '';
      document.getElementById('po_net').value = myPayout.network || '';
    }
  }
  window.savePayout = async function () {
    const payload = {
      method: document.getElementById('po_method').value,
      account_number: document.getElementById('po_num').value.trim(),
      account_name: document.getElementById('po_name').value.trim()
    };
    const net = document.getElementById('po_net').value.trim(); if (net) payload.network = net;
    const bank = document.getElementById('po_bank').value.trim(); if (bank) payload.account_bank = bank;
    try {
      let saved;
      if (myPayout && myPayout.id) saved = await api('/payout-accounts/' + myPayout.id + '/', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      else saved = await api('/payout-accounts/', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      myPayout = saved; toast('Payout details saved.'); renderPayout();
    } catch (e) { toast(e.message || 'Could not save payout details.'); }
  };
  function renderProfile() {'''
    h = h.replace('  function renderProfile() {', INJECT, 1)
    open(HP,'w',encoding='utf-8').write(h)
    print('   OK transporter.html: rider payout form')
else:
    print('   - transporter.html already has payout form')
print('DONE')
FSW_EOF
python3 .fs.py; RC=$?
rm -f .fs.py
if [ $RC -ne 0 ]; then
  echo "X failed; restoring."
  cp -a "$BK/views.py" escrow/api/views.py
  cp -a "$BK/transporter.html" templates/transporter.html
  exit 1
fi
echo ""
echo ">> Applied. Restart the server; hard-refresh transporter.html."
echo ">> Optional commission: add ESCROW_PLATFORM_COMMISSION_RATE = 0.05 to settings (default 0 = none)."
echo ">> Rollback: cp -a $BK/views.py escrow/api/views.py && cp -a $BK/transporter.html templates/transporter.html"
