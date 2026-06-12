from django.db.models import Q
from django.utils import timezone
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django.conf import settings
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated, AllowAny
from escrow.models import Escrow, PaymentTransaction, PayoutAccount
from utils import flutterwave
from .serializers import EscrowSerializer, PayoutAccountSerializer


class EscrowViewSet(viewsets.ModelViewSet):
    queryset = Escrow.objects.all()
    serializer_class = EscrowSerializer
    permission_classes = [IsAuthenticated]
    # Financial records: only safe reads and POST (create + fund/release actions).
    # No raw PUT/PATCH/DELETE — status changes go through fund() / release() only.
    http_method_names = ["get", "post", "head", "options"]

    def get_queryset(self):
        # Visible to the buyer and to the seller (store owner) on the order.
        user = self.request.user
        return Escrow.objects.filter(
            Q(buyer=user) | Q(order__store__owner=user)
        ).distinct()

    def perform_create(self, serializer):
        order = serializer.validated_data.get("order")
        if order is not None and getattr(order, "buyer_id", None) != self.request.user.id:
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied("You can only open escrow for your own order.")
        serializer.save(buyer=self.request.user)

    @action(detail=True, methods=["post"])
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
        escrow = self.get_object()
        if escrow.buyer != request.user:
            return Response(
                {"detail": "Only the buyer can fund this escrow."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if escrow.status != "pending":
            return Response(
                {"detail": f"Cannot fund from status: {escrow.status}."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        escrow.status = "held"
        escrow.funded_at = timezone.now()
        escrow.save()
        return Response(self.get_serializer(escrow).data)

    @action(detail=True, methods=["post"])
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
        })


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
        tx_ref = data.get("tx_ref") or data.get("reference")
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
