#!/usr/bin/env python
"""
add_payments.py  —  Stage 1 of Flutterwave payments (money IN + escrow held).

Run from the folder that contains manage.py:

    python add_payments.py
    python manage.py makemigrations escrow
    python manage.py migrate
    python manage.py check

What it adds:
  - utils/flutterwave.py        : a small Flutterwave v3 client (Standard hosted
                                  checkout for MoMo + card, plus verify).
  - escrow.PaymentTransaction   : a record of every collection/payout attempt.
  - EscrowViewSet.pay action     : buyer hits POST /api/escrows/{id}/pay/ and gets
                                  back a Flutterwave checkout link (MTN/Airtel/card).
  - FlutterwaveWebhookView      : POST /api/payments/flutterwave/webhook/ — verifies
                                  the signature, re-verifies the transaction with
                                  Flutterwave, then marks the escrow as `held`.
  - settings + .env keys         : FLW_PUBLIC_KEY / FLW_SECRET_KEY / FLW_SECRET_HASH,
                                  DEFAULT_CURRENCY=UGX, PLATFORM_FEE_PERCENT.

Stage 2 (next) will add the payout to the seller on release, minus your fee.

Backs up every edited file; aborts cleanly if an anchor doesn't match.
"""
import os
import sys
import shutil
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
STAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
BACKUP = os.path.join(HERE, f".payments_backup_{STAMP}")

ESC_MODELS = os.path.join(HERE, "escrow", "models.py")
ESC_VIEWS = os.path.join(HERE, "escrow", "api", "views.py")
FLW_CLIENT = os.path.join(HERE, "utils", "flutterwave.py")

URLS = None
SETTINGS = None
for root, _d, files in os.walk(HERE):
    if os.path.basename(root) == "agricore_project":
        if "urls.py" in files:
            URLS = os.path.join(root, "urls.py")
        if "settings.py" in files:
            SETTINGS = os.path.join(root, "settings.py")


def die(msg):
    print(f"\n[ABORT] {msg}")
    print("Nothing half-applied. Fix the issue and re-run.")
    sys.exit(1)


def backup(path):
    os.makedirs(BACKUP, exist_ok=True)
    shutil.copy2(path, os.path.join(BACKUP, os.path.relpath(path, HERE).replace(os.sep, "__")))


def edit(path, replacements, label):
    if not path or not os.path.exists(path):
        die(f"Can't find {label}. Run from the folder with manage.py.")
    text = open(path, encoding="utf-8").read()
    for old, new in replacements:
        if new in text and old not in text:
            print(f"[skip] {os.path.relpath(path, HERE)} already has this change")
            continue
        if text.count(old) != 1:
            die(f"Expected exactly one match in {os.path.relpath(path, HERE)} for:\n----\n{old[:140]}\n----\n(found {text.count(old)})")
        text = text.replace(old, new)
    backup(path)
    open(path, "w", encoding="utf-8").write(text)
    print(f"[edit] {os.path.relpath(path, HERE)}")


# ----------------------------------------------------------------------------
FLW_SRC = '''"""Flutterwave (v3) client for Agricore payments.

Collections use Flutterwave **Standard** (hosted checkout), so card details never
touch our server and the hosted page offers MTN/Airtel mobile money and cards.
"""
import uuid
import requests
from decimal import Decimal, ROUND_HALF_UP
from django.conf import settings

FLW_BASE = "https://api.flutterwave.com/v3"


class FlutterwaveError(Exception):
    pass


def _headers():
    return {
        "Authorization": f"Bearer {getattr(settings, 'FLW_SECRET_KEY', '')}",
        "Content-Type": "application/json",
    }


def new_tx_ref(prefix="agc"):
    """A unique, idempotent reference for one payment attempt."""
    return f"{prefix}-{uuid.uuid4().hex[:18]}"


def service_fee(amount):
    """Platform service fee as a Decimal, from settings.PLATFORM_FEE_PERCENT."""
    pct = Decimal(str(getattr(settings, "PLATFORM_FEE_PERCENT", 2.5)))
    return (Decimal(str(amount)) * pct / Decimal("100")).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )


def _handle(resp):
    try:
        data = resp.json()
    except ValueError:
        raise FlutterwaveError(f"Non-JSON response ({resp.status_code}): {resp.text[:200]}")
    if resp.status_code >= 400 or data.get("status") != "success":
        raise FlutterwaveError(data.get("message") or f"HTTP {resp.status_code}")
    return data


def create_payment_link(amount, currency, tx_ref, customer_email,
                        customer_name="", customer_phone="",
                        payment_options="mobilemoneyuganda,card", meta=None):
    """Create a Flutterwave Standard checkout link. Returns the hosted URL."""
    payload = {
        "tx_ref": tx_ref,
        "amount": amount,
        "currency": currency,
        "redirect_url": getattr(settings, "PAYMENT_REDIRECT_URL", ""),
        "payment_options": payment_options,
        "customer": {
            "email": customer_email or "buyer@agricore.app",
            "name": customer_name or "",
            "phonenumber": customer_phone or "",
        },
        "customizations": {"title": "Agricore", "description": "Marketplace escrow payment"},
        "meta": meta or {},
    }
    try:
        resp = requests.post(f"{FLW_BASE}/payments", json=payload, headers=_headers(), timeout=30)
    except requests.RequestException as e:
        raise FlutterwaveError(str(e))
    data = _handle(resp)
    link = (data.get("data") or {}).get("link")
    if not link:
        raise FlutterwaveError("No checkout link returned")
    return link


def verify_transaction(flw_tx_id):
    """Server-side verify a transaction by its Flutterwave id."""
    try:
        resp = requests.get(
            f"{FLW_BASE}/transactions/{flw_tx_id}/verify", headers=_headers(), timeout=30
        )
    except requests.RequestException as e:
        raise FlutterwaveError(str(e))
    return _handle(resp)
'''

PAYMENT_MODEL = '''

class PaymentTransaction(models.Model):
    """Audit record for every money movement tied to an escrow."""

    KIND_CHOICES = [
        ("collection", "Collection (buyer -> platform)"),
        ("payout", "Payout (platform -> seller)"),
    ]
    STATUS_CHOICES = [
        ("pending", "Pending"),
        ("successful", "Successful"),
        ("failed", "Failed"),
    ]

    escrow = models.ForeignKey(
        Escrow, on_delete=models.CASCADE, related_name="transactions"
    )
    kind = models.CharField(max_length=20, choices=KIND_CHOICES, default="collection")
    tx_ref = models.CharField(max_length=100, unique=True)
    flw_id = models.CharField(max_length=64, blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    fee = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    currency = models.CharField(max_length=3, default="UGX")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="pending")
    checkout_link = models.URLField(blank=True)
    raw = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.kind} {self.tx_ref} ({self.status})"
'''

PAY_ACTION = '''    @action(detail=True, methods=["post"])
    def pay(self, request, pk=None):
        """Buyer starts payment for this escrow. Returns a Flutterwave checkout
        link (MTN/Airtel mobile money or card). The webhook confirms it later."""
        escrow = self.get_object()
        if escrow.buyer != request.user:
            return Response(
                {"detail": "Only the buyer can pay for this escrow."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if escrow.status != "pending":
            return Response(
                {"detail": f"Cannot pay from status: {escrow.status}."},
                status=status.HTTP_400_BAD_REQUEST,
            )

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
                customer_email=request.user.email,
                customer_name=request.user.username,
                customer_phone=getattr(request.user, "phone", "") or "",
                meta={"escrow_id": escrow.pk, "txn_id": txn.id},
            )
        except flutterwave.FlutterwaveError as e:
            txn.status = "failed"
            txn.raw = {"error": str(e)}
            txn.save()
            return Response(
                {"detail": f"Could not start payment: {e}"},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        txn.checkout_link = link
        txn.save()
        return Response({
            "checkout_link": link,
            "tx_ref": tx_ref,
            "amount": str(total),
            "service_fee": str(fee),
            "currency": escrow.currency,
        })

    @action(detail=True, methods=["post"])
    def fund(self, request, pk=None):
        """Mark funds as held (in a real system this follows a payment webhook)."""
'''

WEBHOOK_VIEW = '''

class FlutterwaveWebhookView(APIView):
    """Receives Flutterwave payment events. Verifies the signature, re-verifies
    the transaction with Flutterwave, then marks the matching escrow as held.
    Unauthenticated by design (Flutterwave calls it), but signature-protected."""

    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        # 1) Signature check: the header must equal our configured secret hash.
        signature = request.headers.get("verif-hash")
        expected = getattr(settings, "FLW_SECRET_HASH", "")
        if not expected or not signature or signature != expected:
            return Response({"detail": "invalid signature"}, status=status.HTTP_401_UNAUTHORIZED)

        payload = request.data or {}
        data = payload.get("data") or {}
        tx_ref = data.get("tx_ref")
        flw_id = data.get("id")
        if not tx_ref:
            return Response({"detail": "no tx_ref"}, status=status.HTTP_200_OK)

        try:
            txn = PaymentTransaction.objects.get(tx_ref=tx_ref)
        except PaymentTransaction.DoesNotExist:
            return Response({"detail": "unknown tx_ref"}, status=status.HTTP_200_OK)

        # Idempotent: ignore repeat deliveries of an already-settled payment.
        if txn.status == "successful":
            return Response({"detail": "already processed"}, status=status.HTTP_200_OK)

        # 2) Never trust the webhook body alone — verify with Flutterwave directly.
        try:
            verified = flutterwave.verify_transaction(flw_id)
        except flutterwave.FlutterwaveError as e:
            return Response({"detail": f"verify failed: {e}"}, status=status.HTTP_200_OK)

        vdata = verified.get("data") or {}
        amount_ok = abs(float(vdata.get("amount", 0)) - float(txn.amount)) < 0.01
        currency_ok = vdata.get("currency") == txn.currency
        if vdata.get("status") == "successful" and amount_ok and currency_ok:
            txn.status = "successful"
            txn.flw_id = str(flw_id or "")
            txn.raw = verified
            txn.save()
            escrow = txn.escrow
            if escrow.status == "pending":
                escrow.status = "held"
                escrow.funded_at = timezone.now()
                escrow.save()
            return Response({"detail": "ok"}, status=status.HTTP_200_OK)

        txn.status = "failed"
        txn.raw = verified
        txn.save()
        return Response({"detail": "not successful"}, status=status.HTTP_200_OK)
'''

FLW_SETTINGS = '''CLOUDINARY_API_SECRET = env('CLOUDINARY_API_SECRET', default='')

# ==================== FLUTTERWAVE (Payments) ====================
FLW_PUBLIC_KEY = env('FLW_PUBLIC_KEY', default='')
FLW_SECRET_KEY = env('FLW_SECRET_KEY', default='')
FLW_SECRET_HASH = env('FLW_SECRET_HASH', default='')  # set the same value in the Flutterwave webhook settings
DEFAULT_CURRENCY = env('DEFAULT_CURRENCY', default='UGX')
PLATFORM_FEE_PERCENT = env.float('PLATFORM_FEE_PERCENT', default=2.5)
PAYMENT_REDIRECT_URL = env('PAYMENT_REDIRECT_URL', default='https://agricore-frontend.vercel.app/payment/callback')'''


def main():
    # 1) flutterwave client
    os.makedirs(os.path.dirname(FLW_CLIENT), exist_ok=True)
    if os.path.exists(FLW_CLIENT):
        print("[skip] utils/flutterwave.py already exists")
    else:
        open(FLW_CLIENT, "w", encoding="utf-8").write(FLW_SRC)
        print("[new]  utils/flutterwave.py")

    # 2) PaymentTransaction model
    mtext = open(ESC_MODELS, encoding="utf-8").read()
    if "class PaymentTransaction(" not in mtext:
        backup(ESC_MODELS)
        open(ESC_MODELS, "w", encoding="utf-8").write(mtext.rstrip() + "\n" + PAYMENT_MODEL)
        print("[edit] escrow/models.py (+ PaymentTransaction)")
    else:
        print("[skip] escrow/models.py already has PaymentTransaction")

    # 3) escrow views: imports + pay action + webhook view
    vtext = open(ESC_VIEWS, encoding="utf-8").read()
    edits = [
        (
            "from rest_framework.permissions import IsAuthenticated\nfrom escrow.models import Escrow\nfrom .serializers import EscrowSerializer",
            "from django.conf import settings\n"
            "from rest_framework.views import APIView\n"
            "from rest_framework.permissions import IsAuthenticated, AllowAny\n"
            "from escrow.models import Escrow, PaymentTransaction\n"
            "from utils import flutterwave\n"
            "from .serializers import EscrowSerializer",
        ),
        (
            '''    @action(detail=True, methods=["post"])
    def fund(self, request, pk=None):
        """Mark funds as held (in a real system this follows a payment webhook)."""
''',
            PAY_ACTION,
        ),
    ]
    edit(ESC_VIEWS, edits, "escrow/api/views.py")
    # append webhook view (idempotent)
    vtext2 = open(ESC_VIEWS, encoding="utf-8").read()
    if "class FlutterwaveWebhookView(" not in vtext2:
        open(ESC_VIEWS, "a", encoding="utf-8").write(WEBHOOK_VIEW)
        print("[edit] escrow/api/views.py (+ FlutterwaveWebhookView)")

    # 4) urls: import + webhook path
    edit(URLS, [
        (
            "from escrow.api.views import EscrowViewSet",
            "from escrow.api.views import EscrowViewSet, FlutterwaveWebhookView",
        ),
        (
            "    path('api/ai/diagnose-crop/', CropDiagnosisView.as_view(), name='crop_diagnosis'),",
            "    path('api/ai/diagnose-crop/', CropDiagnosisView.as_view(), name='crop_diagnosis'),\n"
            "    path('api/payments/flutterwave/webhook/', FlutterwaveWebhookView.as_view(), name='flw_webhook'),",
        ),
    ], "urls.py")

    # 5) settings: FLW block
    edit(SETTINGS, [
        ("CLOUDINARY_API_SECRET = env('CLOUDINARY_API_SECRET', default='')", FLW_SETTINGS),
    ], "settings.py")

    print(f"\nDone. Backups in {os.path.relpath(BACKUP, HERE)}/")
    print("Next:")
    print("  python manage.py makemigrations escrow")
    print("  python manage.py migrate")
    print("  python manage.py check")


if __name__ == "__main__":
    main()
