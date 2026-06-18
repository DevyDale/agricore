from django.db.models import Q
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated, BasePermission, SAFE_METHODS
from logistics.models import Vehicle, TransportRequest, TransportBid
from .serializers import (
    VehicleSerializer,
    TransportRequestSerializer,
    TransportBidSerializer,
)


class IsRequesterOrReadOnly(BasePermission):
    """Read for anyone allowed to see it; write only for the request's owner."""

    def has_object_permission(self, request, view, obj):
        if request.method in SAFE_METHODS:
            return True
        return obj.requester_id == request.user.id


class IsBidderOrReadOnly(BasePermission):
    """Read for anyone allowed to see it; write only for the bidding transporter."""

    def has_object_permission(self, request, view, obj):
        if request.method in SAFE_METHODS:
            return True
        return obj.transporter_id == request.user.id


class VehicleViewSet(viewsets.ModelViewSet):
    queryset = Vehicle.objects.all()
    serializer_class = VehicleSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Vehicle.objects.filter(transporter=self.request.user)

    def perform_create(self, serializer):
        serializer.save(transporter=self.request.user)


class TransportRequestViewSet(viewsets.ModelViewSet):
    queryset = TransportRequest.objects.all()
    serializer_class = TransportRequestSerializer
    permission_classes = [IsAuthenticated, IsRequesterOrReadOnly]

    def get_queryset(self):
        # Requesters see their own requests; transporters see open requests
        # they can bid on.
        user = self.request.user
        return TransportRequest.objects.filter(
            Q(requester=user) | Q(status="open")
        ).distinct()

    def perform_create(self, serializer):
        serializer.save(requester=self.request.user)


class TransportBidViewSet(viewsets.ModelViewSet):
    queryset = TransportBid.objects.all()
    serializer_class = TransportBidSerializer
    permission_classes = [IsAuthenticated, IsBidderOrReadOnly]

    def get_queryset(self):
        # A transporter sees their own bids; a requester sees bids placed
        # on their requests.
        user = self.request.user
        return TransportBid.objects.filter(
            Q(transporter=user) | Q(transport_request__requester=user)
        ).distinct()

    def perform_create(self, serializer):
        serializer.save(transporter=self.request.user)


import secrets
from django.db.models import Q, Avg, Count
from django.utils import timezone
from django.conf import settings
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.views import APIView
from django.http import HttpResponse
from django.views.decorators.csrf import csrf_exempt
from rest_framework.exceptions import ValidationError, PermissionDenied
from logistics.models import Transporter, DeliveryJob, TransporterReview
from .serializers import TransporterSerializer, DeliveryJobSerializer, TransporterReviewSerializer


class TransporterViewSet(viewsets.ModelViewSet):
    queryset = Transporter.objects.all()
    serializer_class = TransporterSerializer
    permission_classes = [IsAuthenticated]
    http_method_names = ["get", "post", "patch", "head", "options"]

    def get_queryset(self):
        qs = Transporter.objects.select_related("user")
        if self.request.query_params.get("verified") == "true":
            qs = qs.filter(is_verified=True, is_active=True)
        return qs

    def perform_create(self, serializer):
        if Transporter.objects.filter(user=self.request.user).exists():
            raise ValidationError("You already have a transporter profile; update it instead.")
        serializer.save(user=self.request.user)
        u = self.request.user
        if getattr(u, "role", None) != "transporter":
            u.role = "transporter"
            u.save(update_fields=["role"])

    @action(detail=False, methods=["get"])
    def me(self, request):
        t = Transporter.objects.filter(user=request.user).first()
        if not t:
            return Response({"detail": "No transporter profile yet."}, status=status.HTTP_404_NOT_FOUND)
        return Response(self.get_serializer(t).data)

    @action(detail=True, methods=["post"])
    def verify(self, request, pk=None):
        if not request.user.is_staff:
            return Response({"detail": "Only admins can verify transporters."}, status=status.HTTP_403_FORBIDDEN)
        t = self.get_object()
        t.is_verified = True
        t.save(update_fields=["is_verified", "updated_at"])
        return Response(self.get_serializer(t).data)


class DeliveryJobViewSet(viewsets.ModelViewSet):
    queryset = DeliveryJob.objects.all()
    serializer_class = DeliveryJobSerializer
    permission_classes = [IsAuthenticated]
    http_method_names = ["get", "post", "head", "options"]

    def get_queryset(self):
        user = self.request.user
        qs = DeliveryJob.objects.select_related(
            "order", "order__store", "transporter", "transporter__user", "escrow"
        )
        scope = self.request.query_params.get("scope")
        if scope == "open":
            return qs.filter(status="open")
        if scope == "mine_transporter":
            return qs.filter(transporter__user=user)
        # Detail actions must resolve an open job a rider does not yet own (so a
        # rider can view/accept it); list stays scoped to own + assigned jobs.
        if getattr(self, "action", None) in ("retrieve", "accept", "pickup", "cancel", "send_link"):
            return qs.filter(
                Q(created_by=user) | Q(transporter__user=user) | Q(status="open")
            ).distinct()
        return qs.filter(Q(created_by=user) | Q(transporter__user=user)).distinct()

    def perform_create(self, serializer):
        order = serializer.validated_data.get("order")
        if order is None or order.store.owner_id != self.request.user.id:
            raise PermissionDenied("You can only create a delivery job for your own order.")
        if DeliveryJob.objects.filter(order=order).exists():
            raise ValidationError("A delivery job already exists for this order.")
        try:
            escrow = order.escrow
        except Exception:
            escrow = None
        code = f"{secrets.randbelow(900000) + 100000}"
        serializer.save(created_by=self.request.user, escrow=escrow, pickup_code=code, status="open")

    @action(detail=False, methods=["get"])
    def open(self, request):
        qs = DeliveryJob.objects.filter(status="open").select_related("order", "order__store")
        vt = request.query_params.get("vehicle_type")
        if vt:
            qs = qs.filter(Q(vehicle_type_required=vt) | Q(vehicle_type_required=""))
        return Response(self.get_serializer(qs, many=True).data)

    def _my_transporter(self, request):
        return Transporter.objects.filter(user=request.user).first()

    @action(detail=True, methods=["post"])
    def accept(self, request, pk=None):
        job = self.get_object()
        t = self._my_transporter(request)
        if t is None:
            return Response({"detail": "Create a transporter profile first."}, status=status.HTTP_403_FORBIDDEN)
        if not t.is_active:
            return Response({"detail": "Your transporter account is inactive."}, status=status.HTTP_403_FORBIDDEN)
        if job.status != "open":
            return Response({"detail": f"Job is not open (status: {job.status})."}, status=status.HTTP_400_BAD_REQUEST)
        cap = getattr(settings, "TRANSPORTER_UNVERIFIED_MAX", 100000)
        try:
            order_total = float(job.order.total_amount or 0)
        except Exception:
            order_total = 0
        if not t.is_verified and order_total > float(cap):
            return Response(
                {"detail": "This order is above the limit for unverified transporters. Get verified to accept it."},
                status=status.HTTP_403_FORBIDDEN,
            )
        job.transporter = t
        job.status = "accepted"
        job.accepted_at = timezone.now()
        job.save(update_fields=["transporter", "status", "accepted_at", "updated_at"])
        return Response(self.get_serializer(job).data)

    @action(detail=True, methods=["post"])
    def pickup(self, request, pk=None):
        job = self.get_object()
        t = self._my_transporter(request)
        if t is None or job.transporter_id != t.id:
            return Response({"detail": "Only the assigned transporter can mark pickup."}, status=status.HTTP_403_FORBIDDEN)
        if job.status != "accepted":
            return Response({"detail": f"Cannot pick up from status: {job.status}."}, status=status.HTTP_400_BAD_REQUEST)
        supplied = str(request.data.get("pickup_code", "")).strip()
        if not job.pickup_code or supplied != job.pickup_code:
            return Response(
                {"detail": "Incorrect pickup code. Ask the seller for the code shown on their order."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        job.status = "picked_up"
        job.picked_up_at = timezone.now()
        job.save(update_fields=["status", "picked_up_at", "updated_at"])
        sms_sent = False
        try:
            escrow = job.escrow
            if escrow is None:
                try:
                    escrow = job.order.escrow
                except Exception:
                    escrow = None
            if escrow is not None and escrow.status == "held":
                from escrow.api.views import issue_delivery_otp
                sms_sent = issue_delivery_otp(escrow)
        except Exception:
            sms_sent = False
        return Response({
            "detail": "Picked up. The buyer has been sent their delivery code.",
            "sms_sent": sms_sent,
            "job": self.get_serializer(job).data,
        })

    @action(detail=True, methods=["post"])
    def send_link(self, request, pk=None):
        """Seller assigns this delivery to a rider phone and texts a one-time, no-login
        link to work the job. The link cannot fake a handover on its own: pickup still
        needs the seller pickup code and delivery still needs the buyer code."""
        import secrets
        from utils.sms import send_sms, normalize_ug
        job = self.get_object()
        if job.created_by_id != request.user.id:
            return Response({"detail": "Only the seller can send a delivery link."}, status=status.HTTP_403_FORBIDDEN)
        if job.status not in ("open", "accepted"):
            return Response({"detail": f"Cannot send a link from status: {job.status}."}, status=status.HTTP_400_BAD_REQUEST)
        phone = normalize_ug(request.data.get("phone", ""))
        if not phone:
            return Response({"detail": "Enter the rider phone number."}, status=status.HTTP_400_BAD_REQUEST)
        name = str(request.data.get("name", "") or "").strip()[:120]
        if not job.access_token:
            job.access_token = secrets.token_urlsafe(32)
        job.access_phone = phone
        job.access_name = name
        job.status = "accepted"
        job.accepted_at = job.accepted_at or timezone.now()
        job.save(update_fields=["access_token", "access_phone", "access_name", "status", "accepted_at", "updated_at"])
        link = request.build_absolute_uri(f"/rider_link.html?t={job.access_token}")
        msg = f"Agricore: you have a delivery to handle. Open {link} to start. The seller will give you a pickup code."
        sms_sent = False
        try:
            sms_sent = bool(send_sms(phone, msg))
        except Exception:
            sms_sent = False
        return Response({"detail": "Link sent to the rider.", "sms_sent": sms_sent, "link": link, "job": self.get_serializer(job).data})

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        job = self.get_object()
        is_seller = job.created_by_id == request.user.id
        is_rider = bool(job.transporter_id and job.transporter.user_id == request.user.id)
        if not (is_seller or is_rider):
            return Response({"detail": "Not allowed."}, status=status.HTTP_403_FORBIDDEN)
        if job.status in ("delivered", "cancelled"):
            return Response({"detail": f"Cannot cancel from status: {job.status}."}, status=status.HTTP_400_BAD_REQUEST)
        job.status = "cancelled"
        job.save(update_fields=["status", "updated_at"])
        return Response(self.get_serializer(job).data)


class TransporterReviewViewSet(viewsets.ModelViewSet):
    queryset = TransporterReview.objects.all()
    serializer_class = TransporterReviewSerializer
    permission_classes = [IsAuthenticated]
    http_method_names = ["get", "post", "head", "options"]

    def get_queryset(self):
        qs = TransporterReview.objects.all()
        tid = self.request.query_params.get("transporter")
        if tid:
            try:
                qs = qs.filter(transporter_id=int(tid))
            except (TypeError, ValueError):
                pass
        return qs

    def perform_create(self, serializer):
        review = serializer.save(by_user=self.request.user)
        t = review.transporter
        a = TransporterReview.objects.filter(transporter=t).aggregate(avg=Avg("rating"), n=Count("id"))
        t.rating_avg = round(a["avg"] or 0, 2)
        t.rating_count = a["n"] or 0
        t.save(update_fields=["rating_avg", "rating_count", "updated_at"])


def _job_for_token(token):
    if not token:
        return None
    return (
        DeliveryJob.objects
        .select_related("order", "order__store", "escrow")
        .filter(access_token=token)
        .first()
    )


def _do_pickup(job, code):
    """Shared pickup transition (link endpoint + USSD). Validates the seller pickup
    code, marks the job picked up, and fires the buyer's delivery code. (ok, detail)."""
    if job.status != "accepted":
        return False, "Cannot pick up from status: %s." % job.status
    code = str(code or "").strip()
    if not job.pickup_code or code != job.pickup_code:
        return False, "Incorrect pickup code. Ask the seller for the code on their order."
    job.status = "picked_up"
    job.picked_up_at = timezone.now()
    job.save(update_fields=["status", "picked_up_at", "updated_at"])
    escrow = job.escrow
    if escrow is None:
        try:
            escrow = job.order.escrow
        except Exception:
            escrow = None
    try:
        if escrow is not None and escrow.status == "held":
            from escrow.api.views import issue_delivery_otp
            issue_delivery_otp(escrow)
    except Exception:
        pass
    return True, "Picked up. The buyer has been sent their delivery code."


def _do_deliver(job, otp):
    """Shared delivery transition (link endpoint + USSD). Validates the buyer's
    delivery code, confirms delivery, and starts the dispute window. (ok, detail)."""
    from datetime import timedelta
    if job.status != "picked_up":
        return False, "Cannot confirm delivery from status: %s." % job.status
    escrow = job.escrow
    if escrow is None:
        try:
            escrow = job.order.escrow
        except Exception:
            escrow = None
    if escrow is None:
        return False, "No escrow found for this delivery."
    if escrow.status != "held":
        return False, "Cannot confirm delivery from escrow status: %s." % escrow.status
    if not escrow.delivery_otp:
        return False, "No delivery code has been issued yet."
    otp = str(otp or "").strip()
    if otp != escrow.delivery_otp:
        return False, "Incorrect delivery code."
    from escrow.api.views import _dispute_window_hours_for
    hours = _dispute_window_hours_for(escrow.order)
    escrow.delivered_confirmed_at = timezone.now()
    escrow.dispute_deadline = timezone.now() + timedelta(hours=hours)
    escrow.save()
    order = escrow.order
    order.status = "delivered"
    order.save()
    job.status = "delivered"
    job.delivered_at = timezone.now()
    job.save(update_fields=["status", "delivered_at", "updated_at"])
    return True, "Delivery confirmed. Thank you!"


class RiderLinkView(APIView):
    """Public, token-authorised view of one delivery job for an app-less rider."""
    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request, token=None):
        job = _job_for_token(token)
        if job is None:
            return Response({"detail": "This link is not valid."}, status=status.HTTP_404_NOT_FOUND)
        store = getattr(job.order, "store", None)
        if job.status == "accepted":
            nxt = "pickup"
        elif job.status == "picked_up":
            nxt = "deliver"
        else:
            nxt = "none"
        return Response({
            "order_id": job.order_id,
            "status": job.status,
            "next_action": nxt,
            "vehicle_type_required": job.vehicle_type_required,
            "pickup_location": job.pickup_location,
            "drop_location": job.drop_location,
            "offered_fee": str(job.offered_fee),
            "currency": job.currency,
            "rider_name": job.access_name,
            "seller_name": (getattr(store, "owner_name", "") or "") if store else "",
            "seller_phone": (getattr(store, "owner_phone", "") or "") if store else "",
        })


class RiderLinkPickupView(APIView):
    """Rider confirms pickup with the seller pickup code; fires the buyer delivery code."""
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request, token=None):
        job = _job_for_token(token)
        if job is None:
            return Response({"detail": "This link is not valid."}, status=status.HTTP_404_NOT_FOUND)
        ok, detail = _do_pickup(job, request.data.get("pickup_code", ""))
        return Response({"detail": detail, "status": job.status}, status=(status.HTTP_200_OK if ok else status.HTTP_400_BAD_REQUEST))


class RiderLinkDeliverView(APIView):
    """Rider confirms delivery with the buyer code; starts the dispute window."""
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request, token=None):
        job = _job_for_token(token)
        if job is None:
            return Response({"detail": "This link is not valid."}, status=status.HTTP_404_NOT_FOUND)
        ok, detail = _do_deliver(job, request.data.get("otp", ""))
        return Response({"detail": detail, "status": job.status}, status=(status.HTTP_200_OK if ok else status.HTTP_400_BAD_REQUEST))


def _ussd_render(text, jobs, do_pickup, do_deliver):
    """Pure USSD menu logic (no DB/IO) so it is testable against simulated Africa's
    Talking input chains. `jobs` are the rider's active jobs; do_pickup/do_deliver are
    the shared transition helpers. Returns a CON/END response string."""
    parts = text.split("*") if text else []

    def prompt_for(job):
        if job.status == "accepted":
            return "CON Order #%s to %s.\nEnter the pickup code from the seller:" % (job.order_id, job.drop_location or "destination")
        return "CON Order #%s.\nEnter the buyer's delivery code:" % job.order_id

    def process(job, code):
        if job.status == "accepted":
            _ok, detail = do_pickup(job, code)
        elif job.status == "picked_up":
            _ok, detail = do_deliver(job, code)
        else:
            detail = "This delivery is closed."
        return "END " + detail

    if not jobs:
        return "END You have no active Agricore deliveries."
    if len(jobs) == 1:
        job = jobs[0]
        if not parts:
            return prompt_for(job)
        return process(job, parts[-1])
    if not parts:
        lines = ["CON Your deliveries:"]
        for i, j in enumerate(jobs, 1):
            lines.append("%d. Order #%s (%s)" % (i, j.order_id, "pickup" if j.status == "accepted" else "deliver"))
        return "\n".join(lines)
    try:
        job = jobs[int(parts[0]) - 1]
    except (ValueError, IndexError):
        return "END Invalid selection."
    if len(parts) == 1:
        return prompt_for(job)
    return process(job, parts[1])


@csrf_exempt
def ussd_callback(request):
    """Africa's Talking USSD callback. In the AT dashboard, point your shortcode's
    callback URL at https://<host>/api/ussd/ . Stateless: AT sends the full input
    chain in POST 'text' (parts separated by '*'). Responds CON (continue)/END (final)."""
    from utils.sms import normalize_ug
    if request.method != "POST":
        return HttpResponse("END Invalid request.", content_type="text/plain")
    phone = normalize_ug(request.POST.get("phoneNumber", "") or "")
    text = (request.POST.get("text", "") or "").strip()
    jobs = list(
        DeliveryJob.objects
        .select_related("order", "order__store", "escrow")
        .filter(access_phone=phone, status__in=["accepted", "picked_up"])
        .order_by("created_at")
    )
    body = _ussd_render(text, jobs, _do_pickup, _do_deliver)
    return HttpResponse(body, content_type="text/plain")
