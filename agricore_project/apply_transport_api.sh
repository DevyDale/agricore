#!/usr/bin/env bash
# Transporter subsystem -- Patcher 2 of 3: endpoints.
# Adds logistics/api (transporter profile, delivery jobs, reviews), a shared
# delivery-OTP helper, and widens escrow confirm_delivery to accept the assigned
# rider. Then register routes. No migration. Restart afterwards.
set -uo pipefail
if [ ! -f escrow/api/views.py ] || [ ! -f manage.py ]; then
  echo "X Run from the Django project root."; exit 1
fi
URLS="urls.py"; [ -f "$URLS" ] || URLS="agricore_project/urls.py"
if [ ! -f "$URLS" ]; then echo "X Could not find urls.py (looked at ./urls.py and agricore_project/urls.py)."; exit 1; fi
BK="transportapi_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
cp -a escrow/api/views.py "$BK/views.py"
cp -a "$URLS" "$BK/urls.py"
HAD_API=0; [ -d logistics/api ] && { HAD_API=1; cp -a logistics/api "$BK/logistics_api"; }
echo ">> Backup: $BK/  (urls target: $URLS)"
cat > .tapi.py << 'TAPIW_EOF'
import sys, os, ast
def parse_or_die(p):
    try: ast.parse(open(p,encoding='utf-8').read())
    except SyntaxError as e:
        print('   X %s invalid: %s'%(p,e)); sys.exit(1)

SERIALIZERS = r'''from rest_framework import serializers
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
VIEWS = r'''import secrets
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


# 1) logistics/api package + files (create if missing)
os.makedirs('logistics/api', exist_ok=True)
ip='logistics/api/__init__.py'
if not os.path.exists(ip): open(ip,'w').write('')
for path, content in [('logistics/api/serializers.py', SERIALIZERS), ('logistics/api/views.py', VIEWS)]:
    if not os.path.exists(path):
        open(path,'w',encoding='utf-8').write(content); parse_or_die(path)
        print('   OK created', path)
    else:
        print('   - exists, left as-is:', path)

# 2) escrow/api/views.py: shared OTP helper + issue_otp refactor + confirm_delivery widen
VP='escrow/api/views.py'; v=open(VP,encoding='utf-8').read()
if 'issue_delivery_otp' not in v:
    HELPER = (
        'def issue_delivery_otp(escrow):\n'
        '    """Generate the buyer\'s delivery code, persist it, and SMS it to the buyer.\n'
        '    Shared by the seller \'dispatch\' (issue_otp) action and the transporter\n'
        '    \'pickup\' step. Returns True if an SMS backend handled the message."""\n'
        '    import secrets\n'
        '    escrow.delivery_otp = f"{secrets.randbelow(900000) + 100000}"\n'
        '    escrow.otp_issued_at = timezone.now()\n'
        '    escrow.save()\n'
        '    sms_sent = False\n'
        '    try:\n'
        '        from utils.sms import send_sms\n'
        '        phone = getattr(escrow.buyer, "phone", "") or ""\n'
        '        if phone:\n'
        '            msg = f"Agricore: delivery code for order #{escrow.order_id} is {escrow.delivery_otp}. Give it to the courier only when your goods arrive."\n'
        '            sms_sent = bool(send_sms(phone, msg))\n'
        '    except Exception:\n'
        '        sms_sent = False\n'
        '    return sms_sent\n\n\n'
    )
    H_OLD = 'def _dispute_window_hours_for(order):'
    if H_OLD not in v: print('   X escrow helper anchor not found'); sys.exit(1)
    v = v.replace(H_OLD, HELPER + 'def _dispute_window_hours_for(order):', 1)

    # refactor issue_otp body to use the helper
    R_OLD = (
        '        escrow.delivery_otp = f"{secrets.randbelow(900000) + 100000}"\n'
        '        escrow.otp_issued_at = timezone.now()\n'
        '        escrow.dispatch_quantity = str(request.data.get("dispatch_quantity", "") or "").strip()[:120]\n'
        '        escrow.dispatch_note = str(request.data.get("dispatch_note", "") or "").strip()[:2000]\n'
        '        _photo = request.data.get("dispatch_photo")\n'
        '        if _photo is not None and hasattr(_photo, "read"):\n'
        '            escrow.dispatch_photo = _photo\n'
        '        escrow.save()\n'
        '        # Send the code to the buyer by SMS so a feature-phone buyer gets it without the app.\n'
        '        sms_sent = False\n'
        '        try:\n'
        '            from utils.sms import send_sms\n'
        '            phone = getattr(escrow.buyer, "phone", "") or ""\n'
        '            if phone:\n'
        '                msg = f"Agricore: delivery code for order #{escrow.order_id} is {escrow.delivery_otp}. Give it to the courier only when your goods arrive."\n'
        '                sms_sent = bool(send_sms(phone, msg))\n'
        '        except Exception:\n'
        '            sms_sent = False\n'
        '        return Response({"detail": "Dispatched. The buyer has been sent their delivery code.", "sms_sent": sms_sent})'
    )
    R_NEW = (
        '        escrow.dispatch_quantity = str(request.data.get("dispatch_quantity", "") or "").strip()[:120]\n'
        '        escrow.dispatch_note = str(request.data.get("dispatch_note", "") or "").strip()[:2000]\n'
        '        _photo = request.data.get("dispatch_photo")\n'
        '        if _photo is not None and hasattr(_photo, "read"):\n'
        '            escrow.dispatch_photo = _photo\n'
        '        sms_sent = issue_delivery_otp(escrow)\n'
        '        return Response({"detail": "Dispatched. The buyer has been sent their delivery code.", "sms_sent": sms_sent})'
    )
    if R_OLD not in v: print('   X issue_otp body anchor not found'); sys.exit(1)
    v = v.replace(R_OLD, R_NEW, 1)

    # widen confirm_delivery permission
    P_OLD = (
        '        from datetime import timedelta\n'
        '        escrow = self.get_object()\n'
        '        if escrow.order.store.owner_id != request.user.id:\n'
        '            return Response({"detail": "Only the seller can confirm delivery."}, status=status.HTTP_403_FORBIDDEN)'
    )
    P_NEW = (
        '        from datetime import timedelta\n'
        '        escrow = self.get_object()\n'
        '        _job = None\n'
        '        try:\n'
        '            _job = escrow.order.delivery_job\n'
        '        except Exception:\n'
        '            _job = None\n'
        '        _is_seller = escrow.order.store.owner_id == request.user.id\n'
        '        _is_rider = bool(_job is not None and _job.transporter_id and _job.transporter.user_id == request.user.id)\n'
        '        if not (_is_seller or _is_rider):\n'
        '            return Response({"detail": "Only the seller or the assigned transporter can confirm delivery."}, status=status.HTTP_403_FORBIDDEN)'
    )
    if P_OLD not in v: print('   X confirm_delivery permission anchor not found'); sys.exit(1)
    v = v.replace(P_OLD, P_NEW, 1)

    # mark the delivery job delivered too
    J_OLD = (
        '        order.status = "delivered"\n'
        '        order.save()\n'
        '        return Response(self.get_serializer(escrow).data)'
    )
    J_NEW = (
        '        order.status = "delivered"\n'
        '        order.save()\n'
        '        if _job is not None:\n'
        '            _job.status = "delivered"\n'
        '            _job.delivered_at = timezone.now()\n'
        '            _job.save(update_fields=["status", "delivered_at", "updated_at"])\n'
        '        return Response(self.get_serializer(escrow).data)'
    )
    if J_OLD not in v: print('   X confirm_delivery job-mark anchor not found'); sys.exit(1)
    v = v.replace(J_OLD, J_NEW, 1)

    open(VP,'w',encoding='utf-8').write(v); parse_or_die(VP)
    print('   OK escrow/api/views.py: shared OTP helper + rider-aware confirm_delivery')
else:
    print('   - escrow/api/views.py already transporter-aware')

# 3) urls.py: import + register the three routes
UP='urls.py'
if not os.path.exists(UP):
    for cand in ['agricore_project/urls.py']:
        if os.path.exists(cand): UP=cand; break
u=open(UP,encoding='utf-8').read()
if "r'transporters'" not in u:
    IMP_OLD='from escrow.api.views import EscrowViewSet, FlutterwaveWebhookView, PayoutAccountViewSet'
    IMP_NEW=IMP_OLD+'\nfrom logistics.api.views import TransporterViewSet, DeliveryJobViewSet, TransporterReviewViewSet'
    if IMP_OLD not in u: print('   X urls import anchor not found'); sys.exit(1)
    u=u.replace(IMP_OLD,IMP_NEW,1)
    REG_OLD="router.register(r'escrows', EscrowViewSet, basename='escrow')"
    REG_NEW=(REG_OLD
        +"\nrouter.register(r'transporters', TransporterViewSet, basename='transporter')"
        +"\nrouter.register(r'delivery-jobs', DeliveryJobViewSet, basename='deliveryjob')"
        +"\nrouter.register(r'transporter-reviews', TransporterReviewViewSet, basename='transporterreview')")
    if REG_OLD not in u: print('   X urls register anchor not found'); sys.exit(1)
    u=u.replace(REG_OLD,REG_NEW,1)
    open(UP,'w',encoding='utf-8').write(u); parse_or_die(UP)
    print('   OK %s: transporter routes registered' % UP)
else:
    print('   - urls.py already has transporter routes')

print('DONE')
TAPIW_EOF
python3 .tapi.py; RC=$?
rm -f .tapi.py
if [ $RC -ne 0 ]; then
  echo "X failed; restoring."
  cp -a "$BK/views.py" escrow/api/views.py
  cp -a "$BK/urls.py" "$URLS"
  if [ "$HAD_API" -eq 1 ]; then rm -rf logistics/api && cp -a "$BK/logistics_api" logistics/api; else rm -rf logistics/api; fi
  exit 1
fi
echo ""
echo ">> Applied. No migration needed. Run a check then restart:"
echo "     python manage.py check && python manage.py runserver"
echo ">> New endpoints: /api/transporters/ , /api/delivery-jobs/ , /api/transporter-reviews/"
echo "   (Optional setting: TRANSPORTER_UNVERIFIED_MAX = 100000  # UGX cap for unverified riders)"
echo ">> Rollback: cp -a $BK/views.py escrow/api/views.py && cp -a $BK/urls.py $URLS && { [ $HAD_API -eq 1 ] && (rm -rf logistics/api && cp -a $BK/logistics_api logistics/api) || rm -rf logistics/api; }"
