#!/usr/bin/env bash
# FIX for Patcher 2: your logistics/api already had serializers.py/views.py, so the
# new classes were skipped. This APPENDS Transporter/DeliveryJob/Review classes to
# those existing files (idempotent, preserves what's there). No migration. Restart after.
set -uo pipefail
if [ ! -d logistics/api ] || [ ! -f manage.py ]; then
  echo "X Run from the Django project root (needs logistics/api and manage.py)."; exit 1
fi
BK="transportfix_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"; cp -a logistics/api "$BK/logistics_api"
echo ">> Backup: $BK/logistics_api"
cat > .tfix.py << 'TFIXW_EOF'
import sys, os, ast
SER = r'''from rest_framework import serializers
from logistics.models import Transporter, DeliveryJob, TransporterReview


class TransporterSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source="user.username", read_only=True)

    class Meta:
        model = Transporter
        fields = "__all__"
        extra_kwargs = {
            "user": {"read_only": True},
            "is_verified": {"read_only": True},
            "rating_avg": {"read_only": True},
            "rating_count": {"read_only": True},
            "deposit_balance": {"read_only": True},
        }


class DeliveryJobSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeliveryJob
        fields = "__all__"
        extra_kwargs = {
            "created_by": {"read_only": True},
            "transporter": {"read_only": True},
            "status": {"read_only": True},
            "pickup_code": {"read_only": True},
            "escrow": {"read_only": True},
            "accepted_at": {"read_only": True},
            "picked_up_at": {"read_only": True},
            "delivered_at": {"read_only": True},
        }

    def to_representation(self, instance):
        data = super().to_representation(instance)
        request = self.context.get("request")
        viewer = getattr(request, "user", None)
        # The pickup code is the seller's handover proof -- hide it from the rider/others.
        if not (viewer is not None and getattr(instance, "created_by_id", None) == getattr(viewer, "id", None)):
            data.pop("pickup_code", None)
        return data


class TransporterReviewSerializer(serializers.ModelSerializer):
    class Meta:
        model = TransporterReview
        fields = "__all__"
        extra_kwargs = {"by_user": {"read_only": True}}
'''
VIW = r'''import secrets
from django.db.models import Q, Avg, Count
from django.utils import timezone
from django.conf import settings
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
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
'''


os.makedirs('logistics/api', exist_ok=True)
ip='logistics/api/__init__.py'
if not os.path.exists(ip):
    open(ip,'w').write(''); print('   OK created', ip)

def ensure(path, sentinel, block):
    cur = open(path,encoding='utf-8').read() if os.path.exists(path) else ''
    if sentinel in cur:
        print('   - already present, skipped:', path); return
    sep = '' if (cur == '' or cur.endswith('\n')) else '\n'
    open(path,'w',encoding='utf-8').write(cur + sep + '\n\n' + block)
    try:
        ast.parse(open(path,encoding='utf-8').read())
    except SyntaxError as e:
        print('   X %s invalid after append: %s' % (path, e)); sys.exit(1)
    print('   OK appended classes to', path)

ensure('logistics/api/serializers.py', 'class TransporterSerializer', SER)
ensure('logistics/api/views.py', 'class TransporterViewSet', VIW)
print('DONE')
TFIXW_EOF
python3 .tfix.py; RC=$?
rm -f .tfix.py
if [ $RC -ne 0 ]; then echo "X failed; restore: rm -rf logistics/api && cp -a $BK/logistics_api logistics/api"; exit 1; fi
echo ""
echo ">> Fixed. Verify and run:"
echo "     python manage.py check && python manage.py runserver"
echo ">> Rollback: rm -rf logistics/api && cp -a $BK/logistics_api logistics/api"
