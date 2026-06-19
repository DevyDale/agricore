from django.db.models import Q
from django.utils import timezone
from rest_framework import viewsets, status
from drf_spectacular.utils import extend_schema, inline_serializer, OpenApiResponse
from rest_framework import serializers
from rest_framework.decorators import action
from rest_framework.response import Response
from django.conf import settings
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated, AllowAny
from escrow.models import Escrow, PaymentTransaction, PayoutAccount
from utils import flutterwave
from .serializers import EscrowSerializer, PayoutAccountSerializer


def issue_delivery_otp(escrow):
    """Generate the buyer's delivery code, persist it, and SMS it to the buyer.
    Shared by the seller 'dispatch' (issue_otp) action and the transporter
    'pickup' step. Returns True if an SMS backend handled the message."""
    import secrets
    escrow.delivery_otp = f"{secrets.randbelow(900000) + 100000}"
    escrow.otp_issued_at = timezone.now()
    escrow.save()
    sms_sent = False
    try:
        from utils.sms import send_sms
        phone = getattr(escrow.buyer, "phone", "") or ""
        if phone:
            msg = f"Agricore: delivery code for order #{escrow.order_id} is {escrow.delivery_otp}. Give it to the courier only when your goods arrive."
            sms_sent = bool(send_sms(phone, msg))
    except Exception:
        sms_sent = False
    return sms_sent


def _dispute_window_hours_for(order):
    """Pick the dispute window by what is being sold. Perishables and livestock
    (which spoil or lose condition fast in Uganda) get a shorter window so the
    seller is not made to wait days on goods that will not last. Overridable via
    settings: ESCROW_DISPUTE_WINDOW_HOURS, ESCROW_PERISHABLE_WINDOW_HOURS,
    ESCROW_PERISHABLE_CATEGORIES."""
    from django.conf import settings as _s
    default_h = getattr(_s, "ESCROW_DISPUTE_WINDOW_HOURS", 72)
    persh_h = getattr(_s, "ESCROW_PERISHABLE_WINDOW_HOURS", 24)
    keywords = getattr(_s, "ESCROW_PERISHABLE_CATEGORIES", None)
    if keywords is None:
        keywords = ["veg", "fruit", "dairy", "milk", "egg", "poultry", "meat",
                    "fish", "livestock", "perishable", "tomato", "matoke",
                    "banana", "flower", "herb"]
    keywords = [str(k).lower() for k in keywords]
    try:
        for item in order.orderitem_set.all():
            cat = str(getattr(getattr(item, "product", None), "category", "") or "").lower()
            if any(k in cat for k in keywords):
                return persh_h
    except Exception:
        pass
    return default_h


def initiate_seller_payout(escrow):
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

    @extend_schema(request=None, responses=inline_serializer(name="EscrowPayResponse", fields={"checkout_link": serializers.URLField(), "tx_ref": serializers.CharField(), "amount": serializers.CharField(), "service_fee": serializers.CharField(), "currency": serializers.CharField()}))
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

    @extend_schema(request=None, responses=EscrowSerializer)
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

    @extend_schema(request=None, responses=OpenApiResponse(description="Payout to the seller is initiated; the escrow flips to 'released' once Flutterwave confirms the payout via webhook."))
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
        code, body = initiate_seller_payout(escrow)
        return Response(body, status=code)


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
        escrow.dispatch_quantity = str(request.data.get("dispatch_quantity", "") or "").strip()[:120]
        escrow.dispatch_note = str(request.data.get("dispatch_note", "") or "").strip()[:2000]
        _photo = request.data.get("dispatch_photo")
        if _photo is not None and hasattr(_photo, "read"):
            escrow.dispatch_photo = _photo
        sms_sent = issue_delivery_otp(escrow)
        return Response({"detail": "Dispatched. The buyer has been sent their delivery code.", "sms_sent": sms_sent})

    @action(detail=True, methods=["post"])
    def confirm_delivery(self, request, pk=None):
        """Seller enters the buyer's delivery code at hand-over. A correct code is
        proof of receipt and starts the dispute window before auto-release."""
        from datetime import timedelta
        escrow = self.get_object()
        _job = None
        try:
            _job = escrow.order.delivery_job
        except Exception:
            _job = None
        _is_seller = escrow.order.store.owner_id == request.user.id
        _is_rider = bool(_job is not None and _job.transporter_id and _job.transporter.user_id == request.user.id)
        if not (_is_seller or _is_rider):
            return Response({"detail": "Only the seller or the assigned transporter can confirm delivery."}, status=status.HTTP_403_FORBIDDEN)
        if escrow.status != "held":
            return Response({"detail": f"Cannot confirm delivery from status: {escrow.status}."}, status=status.HTTP_400_BAD_REQUEST)
        if not escrow.delivery_otp:
            return Response({"detail": "Dispatch the order first to generate a delivery code."}, status=status.HTTP_400_BAD_REQUEST)
        supplied = str(request.data.get("otp", "")).strip()
        if supplied != escrow.delivery_otp:
            return Response({"detail": "Incorrect delivery code."}, status=status.HTTP_400_BAD_REQUEST)
        hours = _dispute_window_hours_for(escrow.order)
        escrow.delivered_confirmed_at = timezone.now()
        escrow.dispute_deadline = timezone.now() + timedelta(hours=hours)
        escrow.save()
        order = escrow.order
        order.status = "delivered"
        order.save()
        if _job is not None:
            _job.status = "delivered"
            _job.delivered_at = timezone.now()
            _job.save(update_fields=["status", "delivered_at", "updated_at"])
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
        escrow.dispute_quantity = str(request.data.get("dispute_quantity", "") or "").strip()[:120]
        _dphoto = request.data.get("dispute_photo")
        if _dphoto is not None and hasattr(_dphoto, "read"):
            escrow.dispute_photo = _dphoto
        escrow.save()
        return Response(self.get_serializer(escrow).data)


class FlutterwaveWebhookView(APIView):
    """IntaSend webhook (challenge-verified).  [adapter-revision: 2]

    Receives IntaSend collection and Send-Money events. Verifies the IntaSend
    `challenge` against settings.INTASEND_WEBHOOK_CHALLENGE, re-verifies the
    transaction with IntaSend, then advances the matching escrow (collection ->
    held, payout -> released). Unauthenticated by design (IntaSend calls it),
    but challenge-protected. Kept at the existing /api/payments/flutterwave/
    webhook/ URL so nothing else has to change."""

    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        payload = request.data or {}

        # 1) Challenge check: IntaSend echoes the secret you set in the dashboard.
        expected = getattr(settings, "INTASEND_WEBHOOK_CHALLENGE", "")
        challenge = payload.get("challenge")
        if not expected or challenge != expected:
            return Response({"detail": "invalid challenge"}, status=status.HTTP_401_UNAUTHORIZED)

        # 2) Our reference travels as api_ref (collection) or batch_reference (payout).
        tx_ref = payload.get("api_ref") or payload.get("batch_reference")
        invoice_id = payload.get("invoice_id")
        tracking_id = payload.get("tracking_id")
        if not tx_ref:
            return Response({"detail": "no api_ref"}, status=status.HTTP_200_OK)

        try:
            txn = PaymentTransaction.objects.get(tx_ref=tx_ref)
        except PaymentTransaction.DoesNotExist:
            return Response({"detail": "unknown ref"}, status=status.HTTP_200_OK)

        # Idempotent: ignore repeat deliveries of an already-settled payment.
        if txn.status == "successful":
            return Response({"detail": "already processed"}, status=status.HTTP_200_OK)

        # Payout (Send Money) events finalize a release.
        if txn.kind == "payout":
            gid = tracking_id or txn.flw_id
            try:
                vt = flutterwave.verify_transfer(gid)
            except flutterwave.FlutterwaveError as e:
                return Response({"detail": f"verify failed: {e}"}, status=status.HTTP_200_OK)
            tstatus = ((vt.get("data") or {}).get("status") or "").upper()
            if tstatus == "SUCCESSFUL":
                txn.status = "successful"
                txn.flw_id = str(gid or "")
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

        # Collection: never trust the webhook body alone -- verify with IntaSend directly.
        gid = invoice_id or txn.flw_id
        try:
            verified = flutterwave.verify_transaction(gid)
        except flutterwave.FlutterwaveError as e:
            return Response({"detail": f"verify failed: {e}"}, status=status.HTTP_200_OK)

        vdata = verified.get("data") or {}
        try:
            amount_ok = abs(float(vdata.get("amount") or 0) - float(txn.amount)) < 0.01
        except (TypeError, ValueError):
            amount_ok = False
        currency_ok = (vdata.get("currency") or txn.currency) == txn.currency
        if vdata.get("status") == "successful" and amount_ok and currency_ok:
            txn.status = "successful"
            txn.flw_id = str(gid or "")
            txn.raw = verified
            txn.save()
            escrow = txn.escrow
            if escrow.status == "pending":
                escrow.status = "held"
                escrow.funded_at = timezone.now()
                escrow.save()
            return Response({"detail": "ok"}, status=status.HTTP_200_OK)

        if vdata.get("status") == "failed":
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

    @action(detail=False, methods=["get"])
    def banks(self, request):
        """Flutterwave-supported banks for the payout bank picker."""
        country = request.query_params.get("country", "UG")
        try:
            return Response({"banks": flutterwave.list_banks(country)})
        except flutterwave.FlutterwaveError as e:
            return Response({"banks": [], "detail": str(e)})

    def perform_create(self, serializer):
        if PayoutAccount.objects.filter(user=self.request.user).exists():
            from rest_framework.exceptions import ValidationError
            raise ValidationError("You already have a payout account; update it instead.")
        serializer.save(user=self.request.user)
