#!/usr/bin/env python
"""
setup_test_escrow.py — create a real escrow + a payable Flutterwave checkout link.

Run from the folder with manage.py:
    python setup_test_escrow.py

It prints an escrow id and a checkout link. Open the link, pay with a Flutterwave
TEST card, and the webhook should flip that escrow to 'held'.
"""
import os
import django
from decimal import Decimal

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "agricore_project.settings")
django.setup()

from django.contrib.auth import get_user_model
from marketplace.models import Store, Order
from escrow.models import Escrow, PaymentTransaction
from utils import flutterwave

User = get_user_model()

# --- buyer + seller (reused across runs) ---
buyer, _ = User.objects.get_or_create(
    username="test_buyer",
    defaults={"email": "test_buyer@agricore.app"},
)
seller, _ = User.objects.get_or_create(
    username="test_seller",
    defaults={"email": "test_seller@agricore.app"},
)

# --- seller's store (reused) ---
store, _ = Store.objects.get_or_create(
    owner=seller,
    name="Test Farm Store",
    defaults={"description": "Escrow test store"},
)

# --- a fresh order + escrow each run ---
amount = Decimal("1000.00")
order = Order.objects.create(
    buyer=buyer,
    store=store,
    total_amount=amount,
    status="pending",
)
escrow = Escrow.objects.create(
    order=order,
    buyer=buyer,
    amount=amount,
    currency="NGN",
    status="pending",
)

# --- mirror the pay() action: build a collection txn + checkout link ---
fee = flutterwave.service_fee(escrow.amount)
total = escrow.amount + fee
tx_ref = flutterwave.new_tx_ref(f"esc{escrow.pk}")
txn = PaymentTransaction.objects.create(
    escrow=escrow,
    kind="collection",
    tx_ref=tx_ref,
    amount=total,
    fee=fee,
    currency=escrow.currency,
)

try:
    link = flutterwave.create_payment_link(
        amount=float(total),
        currency=escrow.currency,
        tx_ref=tx_ref,
        customer_email=buyer.email,
        customer_name=buyer.username,
        payment_options="card",  # NGN test -> card
        meta={"escrow_id": escrow.pk, "txn_id": txn.id},
    )
except flutterwave.FlutterwaveError as e:
    txn.status = "failed"
    txn.raw = {"error": str(e)}
    txn.save()
    print(f"\n[ERROR] Could not create checkout link: {e}")
    raise SystemExit(1)

txn.checkout_link = link
txn.save()

print("\n" + "=" * 60)
print(f"  Escrow ID : {escrow.pk}")
print(f"  Status    : {escrow.status}  (should become 'held' after payment)")
print(f"  Amount    : {escrow.amount} {escrow.currency}  + fee {fee} = {total}")
print(f"  tx_ref    : {tx_ref}")
print("\n  PAY HERE:")
print(f"  {link}")
print("=" * 60)
print("\nAfter paying with a test card, check status with:")
print('  python manage.py shell -c "from escrow.models import Escrow; '
      f"e=Escrow.objects.get(pk={escrow.pk}); print(e.pk, e.status)\"")
