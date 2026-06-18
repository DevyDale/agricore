#!/usr/bin/env bash
# Verified Trade Chain v1 (backend): extend the escrow app with a delivery OTP,
# a dispute window, and automatic release so a silent buyer no longer traps the
# seller's funds. Additive + surgical. After running: makemigrations + migrate.
set -uo pipefail
if [ ! -f escrow/models.py ] || [ ! -f manage.py ]; then
  echo "X Run from the Django project root (needs escrow/models.py and manage.py)."; exit 1
fi
BK="trade_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"; cp -a escrow "$BK/escrow"
echo ">> Backup: $BK/escrow"
cat > .trade.py << 'TRADEW_EOF'
import sys, ast

def parse_or_die(path):
    try:
        ast.parse(open(path, encoding='utf-8').read())
    except SyntaxError as e:
        print('   X resulting %s is not valid Python: %s' % (path, e)); sys.exit(1)

# ============================ 1) escrow/models.py ============================
MP = 'escrow/models.py'
m = open(MP, encoding='utf-8').read()
if 'delivery_otp' not in m:
    OLD = '''    released_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)'''
    NEW = '''    released_at = models.DateTimeField(blank=True, null=True)
    # ---- Verified Trade Chain v1: delivery verification + dispute window ----
    delivery_otp = models.CharField(max_length=8, blank=True, default="")
    otp_issued_at = models.DateTimeField(blank=True, null=True)
    delivered_confirmed_at = models.DateTimeField(blank=True, null=True)
    dispute_deadline = models.DateTimeField(blank=True, null=True)
    dispute_reason = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)'''
    if OLD not in m:
        print('   X models.py anchor not found -> untouched'); sys.exit(1)
    open(MP, 'w', encoding='utf-8').write(m.replace(OLD, NEW, 1))
    parse_or_die(MP)
    print('   OK models.py: 5 delivery/dispute fields added to Escrow')
else:
    print('   - models.py already has delivery fields')

# ========================= 2) escrow/api/serializers.py =====================
SP = 'escrow/api/serializers.py'
s = open(SP, encoding='utf-8').read()
if 'to_representation' not in s:
    # hide the OTP from everyone except the buyer
    S_OLD = '''class EscrowSerializer(serializers.ModelSerializer):
    class Meta:'''
    S_NEW = '''class EscrowSerializer(serializers.ModelSerializer):
    def to_representation(self, instance):
        data = super().to_representation(instance)
        request = self.context.get("request")
        viewer = getattr(request, "user", None)
        # The delivery OTP is the buyer's proof of receipt -- never expose it to the seller.
        if not (viewer is not None and getattr(instance, "buyer_id", None) == getattr(viewer, "id", None)):
            data.pop("delivery_otp", None)
        return data

    class Meta:'''
    if S_OLD not in s:
        print('   X serializers.py class anchor not found -> untouched'); sys.exit(1)
    s = s.replace(S_OLD, S_NEW, 1)
    # make the new fields read-only (only the actions may set them)
    K_OLD = '''            "released_at": {"read_only": True},
        }'''
    K_NEW = '''            "released_at": {"read_only": True},
            "delivery_otp": {"read_only": True},
            "otp_issued_at": {"read_only": True},
            "delivered_confirmed_at": {"read_only": True},
            "dispute_deadline": {"read_only": True},
            "dispute_reason": {"read_only": True},
        }'''
    if K_OLD not in s:
        print('   X serializers.py extra_kwargs anchor not found -> untouched'); sys.exit(1)
    s = s.replace(K_OLD, K_NEW, 1)
    open(SP, 'w', encoding='utf-8').write(s)
    parse_or_die(SP)
    print('   OK serializers.py: OTP hidden from seller + new fields read-only')
else:
    print('   - serializers.py already patched')

# ============================ 3) escrow/api/views.py ========================
VP = 'escrow/api/views.py'
v = open(VP, encoding='utf-8').read()
if 'initiate_seller_payout' not in v:
    # 3a) module-level helpers before the viewset
    H_OLD = '''from .serializers import EscrowSerializer, PayoutAccountSerializer


class EscrowViewSet(viewsets.ModelViewSet):'''
    H_NEW = '''from .serializers import EscrowSerializer, PayoutAccountSerializer


def initiate_seller_payout(escrow):
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
    }


def release_due_escrows(limit=25):
    """Auto-release escrows whose delivery was confirmed and whose dispute window
    has passed with no dispute. Safe to call often; acts only on due records and
    attempts each at most once (a prior payout attempt excludes it)."""
    now = timezone.now()
    due = (
        Escrow.objects.filter(
            status="held",
            delivered_confirmed_at__isnull=False,
            dispute_deadline__lte=now,
        )
        .exclude(transactions__kind="payout")[:limit]
    )
    released = 0
    for escrow in list(due):
        try:
            code, _body = initiate_seller_payout(escrow)
            if code == status.HTTP_200_OK:
                released += 1
        except Exception:
            pass
    return released


class EscrowViewSet(viewsets.ModelViewSet):'''
    if H_OLD not in v:
        print('   X views.py helper anchor not found -> untouched'); sys.exit(1)
    v = v.replace(H_OLD, H_NEW, 1)

    # 3b) new actions + lazy auto-release sweep, inserted at the end of EscrowViewSet
    M_OLD = '''

class FlutterwaveWebhookView(APIView):'''
    M_NEW = '''

    def list(self, request, *args, **kwargs):
        # Opportunistic auto-release: whenever escrows are listed, release any that
        # are past their dispute window. Works without Celery beat; harmless when none are due.
        try:
            release_due_escrows()
        except Exception:
            pass
        return super().list(request, *args, **kwargs)

    @action(detail=True, methods=["post"])
    def issue_otp(self, request, pk=None):
        """Seller dispatches the order; a delivery code is generated for the buyer.
        The seller must collect this code from the buyer at hand-over."""
        import secrets
        escrow = self.get_object()
        if escrow.order.store.owner_id != request.user.id:
            return Response({"detail": "Only the seller can dispatch this order."}, status=status.HTTP_403_FORBIDDEN)
        if escrow.status != "held":
            return Response({"detail": f"Cannot dispatch from status: {escrow.status}."}, status=status.HTTP_400_BAD_REQUEST)
        escrow.delivery_otp = f"{secrets.randbelow(900000) + 100000}"
        escrow.otp_issued_at = timezone.now()
        escrow.save()
        return Response({"detail": "Dispatched. The buyer can now see their delivery code."})

    @action(detail=True, methods=["post"])
    def confirm_delivery(self, request, pk=None):
        """Seller enters the buyer's delivery code at hand-over. A correct code is
        proof of receipt and starts the dispute window before auto-release."""
        from datetime import timedelta
        escrow = self.get_object()
        if escrow.order.store.owner_id != request.user.id:
            return Response({"detail": "Only the seller can confirm delivery."}, status=status.HTTP_403_FORBIDDEN)
        if escrow.status != "held":
            return Response({"detail": f"Cannot confirm delivery from status: {escrow.status}."}, status=status.HTTP_400_BAD_REQUEST)
        if not escrow.delivery_otp:
            return Response({"detail": "Dispatch the order first to generate a delivery code."}, status=status.HTTP_400_BAD_REQUEST)
        supplied = str(request.data.get("otp", "")).strip()
        if supplied != escrow.delivery_otp:
            return Response({"detail": "Incorrect delivery code."}, status=status.HTTP_400_BAD_REQUEST)
        hours = getattr(settings, "ESCROW_DISPUTE_WINDOW_HOURS", 72)
        escrow.delivered_confirmed_at = timezone.now()
        escrow.dispute_deadline = timezone.now() + timedelta(hours=hours)
        escrow.save()
        order = escrow.order
        order.status = "delivered"
        order.save()
        return Response(self.get_serializer(escrow).data)

    @action(detail=True, methods=["post"])
    def dispute(self, request, pk=None):
        """Buyer flags a problem within the dispute window, freezing auto-release
        so the platform can review the evidence."""
        escrow = self.get_object()
        if escrow.buyer_id != request.user.id:
            return Response({"detail": "Only the buyer can open a dispute."}, status=status.HTTP_403_FORBIDDEN)
        if escrow.status != "held":
            return Response({"detail": f"Cannot dispute from status: {escrow.status}."}, status=status.HTTP_400_BAD_REQUEST)
        escrow.status = "disputed"
        escrow.dispute_reason = str(request.data.get("reason", "")).strip()[:2000]
        escrow.save()
        return Response(self.get_serializer(escrow).data)


class FlutterwaveWebhookView(APIView):'''
    if M_OLD not in v:
        print('   X views.py class-boundary anchor not found -> untouched'); sys.exit(1)
    v = v.replace(M_OLD, M_NEW, 1)

    # 3c) refactor release() to use the shared helper (no behaviour change)
    R_OLD = '''        if escrow.status != "held":
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
    R_NEW = '''        code, body = initiate_seller_payout(escrow)
        return Response(body, status=code)'''
    if R_OLD not in v:
        print('   X views.py release-block anchor not found -> untouched'); sys.exit(1)
    v = v.replace(R_OLD, R_NEW, 1)

    open(VP, 'w', encoding='utf-8').write(v)
    parse_or_die(VP)
    print('   OK views.py: helpers + issue_otp/confirm_delivery/dispute + auto-release; release refactored')
else:
    print('   - views.py already patched')

# ============================ 4) escrow/tasks.py ============================
TP = 'escrow/tasks.py'
import os
if not os.path.exists(TP):
    open(TP, 'w', encoding='utf-8').write(
        'from celery import shared_task\n\n\n'
        '@shared_task\n'
        'def auto_release_due_escrows():\n'
        '    """Periodic task: release escrows whose dispute window has elapsed.\n'
        '    Wire into Celery beat, or rely on the lazy sweep in EscrowViewSet.list()."""\n'
        '    from escrow.api.views import release_due_escrows\n'
        '    return release_due_escrows()\n'
    )
    parse_or_die(TP)
    print('   OK tasks.py created (Celery auto-release task)')
else:
    print('   - tasks.py already exists (left as-is)')

print('DONE')
TRADEW_EOF
python3 .trade.py; RC=$?
rm -f .trade.py
if [ $RC -ne 0 ]; then echo "X failed; restore: rm -rf escrow && cp -a $BK/escrow escrow"; exit 1; fi
echo ""
echo ">> Code applied. Now create + apply the migration:"
echo "     python manage.py makemigrations escrow && python manage.py migrate"
echo "     python manage.py check"
echo "   then restart the server."
echo ">> Rollback: rm -rf escrow && cp -a $BK/escrow escrow"
