#!/usr/bin/env python
"""
complete_payments.py  —  Finish the Flutterwave payment system in one pass.

This replaces the earlier finish_payments.py + add_payout.py (which mis-targeted a
stale backup folder). It applies everything still missing:

  Stage 1 remainder:
    - webhook ROUTE in urls.py
    - FLUTTERWAVE settings block in settings.py
  Stage 2 (money out):
    - escrow.PayoutAccount + /api/payout-accounts/ endpoint
    - flutterwave.initiate_transfer / verify_transfer
    - release rewired to pay the seller (fee retained); escrow -> 'released' only
      after the transfer webhook confirms
    - webhook now handles BOTH funding (charge) and payout (transfer) events

It targets your REAL project files (next to manage.py) and ignores hidden/backup
folders. Validates every change first; writes nothing unless all checks pass.

Run from the folder with manage.py:

    python complete_payments.py
    python manage.py makemigrations escrow
    python manage.py migrate
    python manage.py check
"""
import os
import sys
import shutil
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
STAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
BACKUP = os.path.join(HERE, f".pay_complete_backup_{STAMP}")


def resolve(rel_parts, fallback_name=None):
    """Resolve a project file by its path next to manage.py, ignoring hidden dirs."""
    direct = os.path.join(HERE, *rel_parts)
    if os.path.isfile(direct):
        return direct
    if fallback_name:
        for root, dirs, files in os.walk(HERE):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            if os.path.basename(root) == "agricore_project" and fallback_name in files:
                return os.path.join(root, fallback_name)
    return direct  # may not exist; caller checks


URLS = resolve(["agricore_project", "urls.py"], "urls.py")
SETTINGS = resolve(["agricore_project", "settings.py"], "settings.py")
ESC_MODELS = os.path.join(HERE, "escrow", "models.py")
ESC_VIEWS = os.path.join(HERE, "escrow", "api", "views.py")
ESC_SER = os.path.join(HERE, "escrow", "api", "serializers.py")
FLW = os.path.join(HERE, "utils", "flutterwave.py")

# -------------------------- code blocks --------------------------
FLW_SETTINGS_BLOCK = '''CLOUDINARY_API_SECRET = env('CLOUDINARY_API_SECRET', default='')

# ==================== FLUTTERWAVE (Payments) ====================
FLW_PUBLIC_KEY = env('FLW_PUBLIC_KEY', default='')
FLW_SECRET_KEY = env('FLW_SECRET_KEY', default='')
FLW_SECRET_HASH = env('FLW_SECRET_HASH', default='')  # same value as the Flutterwave dashboard webhook hash
DEFAULT_CURRENCY = env('DEFAULT_CURRENCY', default='UGX')
PLATFORM_FEE_PERCENT = env.float('PLATFORM_FEE_PERCENT', default=2.5)
PAYMENT_REDIRECT_URL = env('PAYMENT_REDIRECT_URL', default='https://agricore-frontend.vercel.app/payment/callback')'''

PAYOUT_MODEL = '''

class PayoutAccount(models.Model):
    """Where a seller receives their money (mobile money or bank)."""

    METHOD_CHOICES = [("momo", "Mobile Money"), ("bank", "Bank")]

    user = models.OneToOneField(
        CustomUser, on_delete=models.CASCADE, related_name="payout_account"
    )
    method = models.CharField(max_length=10, choices=METHOD_CHOICES, default="momo")
    account_bank = models.CharField(
        max_length=20, default="MPS",
        help_text='"MPS" for mobile money, or a bank code for bank payouts',
    )
    account_number = models.CharField(
        max_length=40,
        help_text="Mobile number (international format) for MoMo, or bank account number",
    )
    account_name = models.CharField(max_length=120)
    network = models.CharField(
        max_length=20, blank=True, help_text="MTN or AIRTEL (mobile money only)"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Payout for {self.user} ({self.method})"
'''

PAYOUT_SERIALIZER = '''

class PayoutAccountSerializer(serializers.ModelSerializer):
    class Meta:
        model = PayoutAccount
        fields = "__all__"
        extra_kwargs = {"user": {"read_only": True}}
'''

PAYOUT_VIEWSET = '''

class PayoutAccountViewSet(viewsets.ModelViewSet):
    """A seller manages their own payout destination (one per user)."""

    serializer_class = PayoutAccountSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return PayoutAccount.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        if PayoutAccount.objects.filter(user=self.request.user).exists():
            from rest_framework.exceptions import ValidationError
            raise ValidationError("You already have a payout account; update it instead.")
        serializer.save(user=self.request.user)
'''

TRANSFER_FUNCS = '''

def initiate_transfer(amount, currency, account_bank, account_number,
                      beneficiary_name, reference, narration="Agricore payout", meta=None):
    """Send a payout (Transfer). For mobile money use account_bank="MPS" and
    account_number = the recipient's phone in international format."""
    payload = {
        "account_bank": account_bank,
        "account_number": account_number,
        "amount": amount,
        "currency": currency,
        "beneficiary_name": beneficiary_name,
        "reference": reference,
        "narration": narration,
    }
    if meta:
        payload["meta"] = meta
    try:
        resp = requests.post(f"{FLW_BASE}/transfers", json=payload, headers=_headers(), timeout=30)
    except requests.RequestException as e:
        raise FlutterwaveError(str(e))
    return _handle(resp)


def verify_transfer(transfer_id):
    """Check a payout's status by its Flutterwave transfer id."""
    try:
        resp = requests.get(f"{FLW_BASE}/transfers/{transfer_id}", headers=_headers(), timeout=30)
    except requests.RequestException as e:
        raise FlutterwaveError(str(e))
    return _handle(resp)
'''

OLD_RELEASE = '''    @action(detail=True, methods=["post"])
    def release(self, request, pk=None):
        """Buyer confirms delivery and releases funds to the seller."""
        escrow = self.get_object()
        if escrow.buyer != request.user:
            return Response(
                {"detail": "Only the buyer can release funds."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if escrow.status != "held":
            return Response(
                {"detail": f"Cannot release from status: {escrow.status}."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        escrow.status = "released"
        escrow.released_at = timezone.now()
        escrow.save()
        return Response(self.get_serializer(escrow).data)'''

NEW_RELEASE = '''    @action(detail=True, methods=["post"])
    def release(self, request, pk=None):
        """Buyer confirms delivery -> pay the seller. The escrow flips to
        'released' only when Flutterwave confirms the payout (via webhook)."""
        escrow = self.get_object()
        if escrow.buyer != request.user:
            return Response(
                {"detail": "Only the buyer can release funds."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if escrow.status != "held":
            return Response(
                {"detail": f"Cannot release from status: {escrow.status}."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if escrow.transactions.filter(kind="payout", status__in=["pending", "successful"]).exists():
            return Response(
                {"detail": "A payout for this escrow is already in progress."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        seller = escrow.order.store.owner
        payout_account = getattr(seller, "payout_account", None)
        if payout_account is None:
            return Response(
                {"detail": "The seller has not set up a payout account yet."},
                status=status.HTTP_409_CONFLICT,
            )

        tx_ref = flutterwave.new_tx_ref(f"pay{escrow.pk}")
        txn = PaymentTransaction.objects.create(
            escrow=escrow,
            kind="payout",
            tx_ref=tx_ref,
            amount=escrow.amount,
            fee=0,
            currency=escrow.currency,
        )
        try:
            resp = flutterwave.initiate_transfer(
                amount=float(escrow.amount),
                currency=escrow.currency,
                account_bank=payout_account.account_bank,
                account_number=payout_account.account_number,
                beneficiary_name=payout_account.account_name,
                reference=tx_ref,
                narration=f"Agricore order #{escrow.order_id}",
            )
        except flutterwave.FlutterwaveError as e:
            txn.status = "failed"
            txn.raw = {"error": str(e)}
            txn.save()
            return Response(
                {"detail": f"Could not start payout: {e}"},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        txn.flw_id = str((resp.get("data") or {}).get("id") or "")
        txn.raw = resp
        txn.save()
        return Response({
            "detail": "Payout initiated. The escrow will show 'released' once it completes.",
            "transfer_status": (resp.get("data") or {}).get("status"),
            "tx_ref": tx_ref,
        })'''

WEBHOOK_OLD = '''        if txn.status == "successful":
            return Response({"detail": "already processed"}, status=status.HTTP_200_OK)

        # 2) Never trust the webhook body alone — verify with Flutterwave directly.
        try:
            verified = flutterwave.verify_transaction(flw_id)'''

WEBHOOK_NEW = '''        if txn.status == "successful":
            return Response({"detail": "already processed"}, status=status.HTTP_200_OK)

        # Payout (transfer) events finalize a release.
        if txn.kind == "payout":
            try:
                vt = flutterwave.verify_transfer(flw_id)
            except flutterwave.FlutterwaveError as e:
                return Response({"detail": f"verify failed: {e}"}, status=status.HTTP_200_OK)
            tstatus = ((vt.get("data") or {}).get("status") or "").upper()
            if tstatus == "SUCCESSFUL":
                txn.status = "successful"
                txn.flw_id = str(flw_id or "")
                txn.raw = vt
                txn.save()
                escrow = txn.escrow
                if escrow.status == "held":
                    escrow.status = "released"
                    escrow.released_at = timezone.now()
                    escrow.save()
                return Response({"detail": "payout ok"}, status=status.HTTP_200_OK)
            if tstatus in ("FAILED", "ERROR"):
                txn.status = "failed"
                txn.raw = vt
                txn.save()
            return Response({"detail": f"payout {tstatus.lower() or 'pending'}"}, status=status.HTTP_200_OK)

        # 2) Never trust the webhook body alone — verify with Flutterwave directly.
        try:
            verified = flutterwave.verify_transaction(flw_id)'''

# (path, old, new, skip_marker)
REPLACEMENTS = [
    (SETTINGS, "CLOUDINARY_API_SECRET = env('CLOUDINARY_API_SECRET', default='')", FLW_SETTINGS_BLOCK, "FLW_SECRET_KEY"),
    (URLS, "from escrow.api.views import EscrowViewSet\n",
     "from escrow.api.views import EscrowViewSet, FlutterwaveWebhookView, PayoutAccountViewSet\n", "PayoutAccountViewSet"),
    (URLS, "    path('api/', include(router.urls)),",
     "    path('api/', include(router.urls)),\n    path('api/payments/flutterwave/webhook/', FlutterwaveWebhookView.as_view(), name='flw_webhook'),",
     "api/payments/flutterwave/webhook/"),
    (URLS, "router.register(r'escrows', EscrowViewSet, basename='escrow')",
     "router.register(r'escrows', EscrowViewSet, basename='escrow')\nrouter.register(r'payout-accounts', PayoutAccountViewSet, basename='payoutaccount')",
     "payout-accounts"),
    (ESC_SER, "from escrow.models import Escrow\n", "from escrow.models import Escrow, PayoutAccount\n", "Escrow, PayoutAccount"),
    (ESC_VIEWS, "from escrow.models import Escrow, PaymentTransaction\n",
     "from escrow.models import Escrow, PaymentTransaction, PayoutAccount\n", "PaymentTransaction, PayoutAccount"),
    (ESC_VIEWS, "from .serializers import EscrowSerializer\n",
     "from .serializers import EscrowSerializer, PayoutAccountSerializer\n", "EscrowSerializer, PayoutAccountSerializer"),
    (ESC_VIEWS, OLD_RELEASE, NEW_RELEASE, "Payout initiated. The escrow will show"),
    (ESC_VIEWS, '        tx_ref = data.get("tx_ref")\n        flw_id = data.get("id")',
     '        tx_ref = data.get("tx_ref") or data.get("reference")\n        flw_id = data.get("id")', 'data.get("reference")'),
    (ESC_VIEWS, WEBHOOK_OLD, WEBHOOK_NEW, 'txn.kind == "payout"'),
]

# (path, block, skip_marker)
APPENDS = [
    (ESC_MODELS, PAYOUT_MODEL, "class PayoutAccount("),
    (ESC_SER, PAYOUT_SERIALIZER, "class PayoutAccountSerializer("),
    (ESC_VIEWS, PAYOUT_VIEWSET, "class PayoutAccountViewSet("),
    (FLW, TRANSFER_FUNCS, "def initiate_transfer"),
]


def main():
    needed = {SETTINGS, URLS, ESC_MODELS, ESC_VIEWS, ESC_SER, FLW}
    for p in needed:
        if not os.path.isfile(p):
            print(f"[ABORT] Required file not found: {p}\nRun from the folder that contains manage.py.")
            sys.exit(1)

    planned = {p: open(p, encoding="utf-8").read() for p in needed}
    problems = []

    for path, old, new, marker in REPLACEMENTS:
        text = planned[path]
        if marker in text:
            continue
        if text.count(old) != 1:
            problems.append(f"{os.path.relpath(path, HERE)}: anchor not unique (found {text.count(old)}):\n      {old[:90]}")
            continue
        planned[path] = text.replace(old, new)

    for path, block, marker in APPENDS:
        text = planned[path]
        if marker in text:
            continue
        planned[path] = text.rstrip() + "\n" + block

    if problems:
        print("[ABORT] Nothing written. Issues:")
        for p in problems:
            print("  - " + p)
        sys.exit(1)

    os.makedirs(BACKUP, exist_ok=True)
    changed = False
    for path, new_text in planned.items():
        original = open(path, encoding="utf-8").read()
        if new_text == original:
            print(f"[ok]   {os.path.relpath(path, HERE)} already complete")
            continue
        shutil.copy2(path, os.path.join(BACKUP, os.path.relpath(path, HERE).replace(os.sep, "__")))
        open(path, "w", encoding="utf-8").write(new_text)
        print(f"[edit] {os.path.relpath(path, HERE)}")
        changed = True

    print(f"\nDone. {'Backups in ' + os.path.relpath(BACKUP, HERE) + '/' if changed else '(no changes needed)'}")
    print("Next:")
    print("  python manage.py makemigrations escrow")
    print("  python manage.py migrate")
    print("  python manage.py check")


if __name__ == "__main__":
    main()
