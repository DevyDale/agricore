#!/usr/bin/env python
"""
test_payout.py — set up the seller's payout account and release a held escrow.

Run from the manage.py folder (server + ngrok still running):
    python test_payout.py

Uses Flutterwave's Nigerian test bank (Access Bank 044, test account 0690000040)
and a `_PMCK` reference so test mode mocks the transfer as successful (resolves
after ~10 min, which then fires a transfer webhook -> escrow 'released').
"""
import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "agricore_project.settings")
django.setup()

from escrow.models import Escrow, PaymentTransaction, PayoutAccount
from utils import flutterwave

# 1) find a held escrow (the one we funded)
escrow = Escrow.objects.filter(status="held").order_by("-pk").first()
if not escrow:
    print("No 'held' escrow found. Fund one first (setup_test_escrow.py + pay).")
    raise SystemExit(1)

seller = escrow.order.store.owner

# 2) ensure the seller has a payout destination (Nigerian test bank)
payout, created = PayoutAccount.objects.get_or_create(
    user=seller,
    defaults=dict(
        method="bank",
        account_bank="044",            # Access Bank (Flutterwave test bank)
        account_number="0690000040",   # Flutterwave test account number
        account_name="Test Seller",
        network="",
    ),
)
print(f"Payout account for {seller.username}: "
      f"{payout.method} {payout.account_bank}/{payout.account_number} "
      f"({'created' if created else 'existing'})")

# 3) guard against a double payout
if escrow.transactions.filter(kind="payout", status__in=["pending", "successful"]).exists():
    print("A payout for this escrow is already in progress — not starting another.")
    raise SystemExit(0)

# 4) initiate the transfer.  '_PMCK' suffix => test-mode mock SUCCESS (~10 min).
#    (Production code uses a plain reference; this suffix is test-mode only.)
tx_ref = flutterwave.new_tx_ref(f"pay{escrow.pk}") + "_PMCK"
txn = PaymentTransaction.objects.create(
    escrow=escrow, kind="payout", tx_ref=tx_ref,
    amount=escrow.amount, fee=0, currency=escrow.currency,
)

print(f"\nReleasing escrow #{escrow.pk}: paying {escrow.amount} {escrow.currency} "
      f"to {seller.username}")
print(f"Transfer reference: {tx_ref}")

try:
    resp = flutterwave.initiate_transfer(
        amount=float(escrow.amount),
        currency=escrow.currency,
        account_bank=payout.account_bank,
        account_number=payout.account_number,
        beneficiary_name=payout.account_name,
        reference=tx_ref,
        narration=f"Agricore order #{escrow.order_id}",
    )
except flutterwave.FlutterwaveError as e:
    txn.status = "failed"
    txn.raw = {"error": str(e)}
    txn.save()
    print("\n[Flutterwave error] " + str(e))
    print("- 'insufficient'/'balance' -> your TEST wallet needs funding "
          "(mocked card collections don't fund it).")
    print("- 'IP'/'whitelist'        -> add your IP under Settings -> Whitelisted IP addresses.")
    raise SystemExit(1)

txn.flw_id = str((resp.get("data") or {}).get("id") or "")
txn.raw = resp
txn.save()

print("\n--- Flutterwave response ---")
print("status :", resp.get("status"), "|", resp.get("message"))
print("transfer status:", (resp.get("data") or {}).get("status"))
print("transfer id    :", (resp.get("data") or {}).get("id"))
print("\nIf transfer status is NEW/PENDING/QUEUED, the payout was accepted.")
print("With the _PMCK reference, test mode mock-completes it after ~10 min,")
print("firing a transfer webhook that flips the escrow to 'released'.")
print(f"\nCheck later with:")
print(f'  python manage.py shell -c "from escrow.models import Escrow; '
      f"e=Escrow.objects.get(pk={escrow.pk}); print(e.pk, e.status)\"")
