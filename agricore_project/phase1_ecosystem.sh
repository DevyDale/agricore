#!/usr/bin/env bash
#
# phase1_ecosystem.sh
# -------------------
# Phase 1 of evolving Agricore toward the African Agricultural Commerce
# Ecosystem. Adds three NEW, self-contained Django apps:
#
#   marketprices  - Module 2: live/regional/export commodity prices
#   logistics     - Module 3: transport booking + transporter bidding
#   escrow        - Module 5: escrow hold/release on marketplace orders
#
# It does NOT modify any existing model files. The only edits to existing
# files are registering the apps in settings.py (INSTALLED_APPS) and wiring
# routes in urls.py. Both are backed up first and the edits are idempotent.
#
# Run from your project root (the directory containing manage.py):
#   bash phase1_ecosystem.sh
#
set -euo pipefail

if [ ! -f manage.py ]; then
  echo "ERROR: run this from your project root (where manage.py lives)." >&2
  exit 1
fi

SETTINGS="agricore_project/settings.py"
URLS="agricore_project/urls.py"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".phase1_backups_$TS"

mkdir -p "$BACKUP_DIR/agricore_project"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$BACKUP_DIR/$SETTINGS"
[ -f "$URLS" ] && cp "$URLS" "$BACKUP_DIR/$URLS"
echo "Backed up settings.py and urls.py to $BACKUP_DIR/"

# ---------------------------------------------------------------------------
# marketprices app  (Module 2)
# ---------------------------------------------------------------------------
mkdir -p marketprices/api marketprices/migrations
: > marketprices/__init__.py
: > marketprices/api/__init__.py
: > marketprices/migrations/__init__.py

cat > marketprices/apps.py <<'MPAPPS'
from django.apps import AppConfig


class MarketPricesConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "marketprices"
MPAPPS

cat > marketprices/models.py <<'MPMODELS'
from django.db import models


class MarketPrice(models.Model):
    """Reference commodity prices by country/region (Module 2)."""

    PRICE_TYPE_CHOICES = [
        ("local", "Local"),
        ("regional", "Regional"),
        ("export", "Export"),
    ]

    commodity = models.CharField(max_length=100)            # e.g. "Maize"
    variety = models.CharField(max_length=100, blank=True)
    country = models.CharField(max_length=100)
    region = models.CharField(max_length=100, blank=True)
    price_type = models.CharField(
        max_length=20, choices=PRICE_TYPE_CHOICES, default="local"
    )
    price = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="USD")
    unit = models.CharField(max_length=20, default="ton")   # per ton/kg/bag
    source = models.CharField(max_length=255, blank=True)
    recorded_on = models.DateField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-recorded_on", "commodity"]
        indexes = [
            models.Index(fields=["commodity", "country", "recorded_on"]),
        ]

    def __str__(self):
        return f"{self.commodity} {self.price}{self.currency}/{self.unit} ({self.country}, {self.recorded_on})"
MPMODELS

cat > marketprices/admin.py <<'MPADMIN'
from django.contrib import admin
from marketprices.models import MarketPrice

admin.site.register(MarketPrice)
MPADMIN

cat > marketprices/api/serializers.py <<'MPSER'
from rest_framework import serializers
from marketprices.models import MarketPrice


class MarketPriceSerializer(serializers.ModelSerializer):
    class Meta:
        model = MarketPrice
        fields = "__all__"
MPSER

cat > marketprices/api/views.py <<'MPVIEWS'
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated, IsAdminUser
from marketprices.models import MarketPrice
from .serializers import MarketPriceSerializer


class MarketPriceViewSet(viewsets.ModelViewSet):
    """Read for any authenticated user; writes restricted to staff,
    since prices are shared reference data, not per-user records.

    Optional filters: ?commodity=Maize&country=Kenya
    """

    queryset = MarketPrice.objects.all()
    serializer_class = MarketPriceSerializer

    def get_permissions(self):
        if self.action in ("list", "retrieve"):
            return [IsAuthenticated()]
        return [IsAdminUser()]

    def get_queryset(self):
        qs = MarketPrice.objects.all()
        commodity = self.request.query_params.get("commodity")
        country = self.request.query_params.get("country")
        price_type = self.request.query_params.get("price_type")
        if commodity:
            qs = qs.filter(commodity__iexact=commodity)
        if country:
            qs = qs.filter(country__iexact=country)
        if price_type:
            qs = qs.filter(price_type=price_type)
        return qs
MPVIEWS

# ---------------------------------------------------------------------------
# logistics app  (Module 3)
# ---------------------------------------------------------------------------
mkdir -p logistics/api logistics/migrations
: > logistics/__init__.py
: > logistics/api/__init__.py
: > logistics/migrations/__init__.py

cat > logistics/apps.py <<'LGAPPS'
from django.apps import AppConfig


class LogisticsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "logistics"
LGAPPS

cat > logistics/models.py <<'LGMODELS'
from django.db import models
from accounts.models import CustomUser
from marketplace.models import Order


class Vehicle(models.Model):
    VEHICLE_TYPES = [
        ("truck", "Truck"),
        ("pickup", "Pickup"),
        ("van", "Van"),
        ("refrigerated", "Refrigerated"),
    ]
    transporter = models.ForeignKey(
        CustomUser, on_delete=models.CASCADE, related_name="vehicles"
    )
    vehicle_type = models.CharField(max_length=20, choices=VEHICLE_TYPES)
    registration_number = models.CharField(max_length=50)
    capacity_kg = models.DecimalField(
        max_digits=10, decimal_places=2, blank=True, null=True
    )
    is_available = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.get_vehicle_type_display()} {self.registration_number}"


class TransportRequest(models.Model):
    STATUS_CHOICES = [
        ("open", "Open"),
        ("assigned", "Assigned"),
        ("in_transit", "In transit"),
        ("delivered", "Delivered"),
        ("cancelled", "Cancelled"),
    ]
    requester = models.ForeignKey(
        CustomUser, on_delete=models.CASCADE, related_name="transport_requests"
    )
    order = models.ForeignKey(
        Order,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="transport_requests",
    )
    pickup_location = models.CharField(max_length=255)
    dropoff_location = models.CharField(max_length=255)
    cargo_description = models.CharField(max_length=255, blank=True)
    weight_kg = models.DecimalField(
        max_digits=10, decimal_places=2, blank=True, null=True
    )
    pickup_date = models.DateField(blank=True, null=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="open")
    assigned_bid = models.ForeignKey(
        "TransportBid",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="assigned_for",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]


class TransportBid(models.Model):
    transport_request = models.ForeignKey(
        TransportRequest, on_delete=models.CASCADE, related_name="bids"
    )
    transporter = models.ForeignKey(
        CustomUser, on_delete=models.CASCADE, related_name="transport_bids"
    )
    vehicle = models.ForeignKey(
        Vehicle, on_delete=models.SET_NULL, null=True, blank=True
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="USD")
    estimated_days = models.IntegerField(blank=True, null=True)
    note = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["amount"]
LGMODELS

cat > logistics/admin.py <<'LGADMIN'
from django.contrib import admin
from logistics.models import Vehicle, TransportRequest, TransportBid

admin.site.register(Vehicle)
admin.site.register(TransportRequest)
admin.site.register(TransportBid)
LGADMIN

cat > logistics/api/serializers.py <<'LGSER'
from rest_framework import serializers
from logistics.models import Vehicle, TransportRequest, TransportBid


class VehicleSerializer(serializers.ModelSerializer):
    class Meta:
        model = Vehicle
        fields = "__all__"
        extra_kwargs = {"transporter": {"read_only": True}}


class TransportRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = TransportRequest
        fields = "__all__"
        extra_kwargs = {"requester": {"read_only": True}}


class TransportBidSerializer(serializers.ModelSerializer):
    class Meta:
        model = TransportBid
        fields = "__all__"
        extra_kwargs = {"transporter": {"read_only": True}}
LGSER

cat > logistics/api/views.py <<'LGVIEWS'
from django.db.models import Q
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from logistics.models import Vehicle, TransportRequest, TransportBid
from .serializers import (
    VehicleSerializer,
    TransportRequestSerializer,
    TransportBidSerializer,
)


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
    permission_classes = [IsAuthenticated]

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
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        # A transporter sees their own bids; a requester sees bids placed
        # on their requests.
        user = self.request.user
        return TransportBid.objects.filter(
            Q(transporter=user) | Q(transport_request__requester=user)
        ).distinct()

    def perform_create(self, serializer):
        serializer.save(transporter=self.request.user)
LGVIEWS

# ---------------------------------------------------------------------------
# escrow app  (Module 5)
# ---------------------------------------------------------------------------
mkdir -p escrow/api escrow/migrations
: > escrow/__init__.py
: > escrow/api/__init__.py
: > escrow/migrations/__init__.py

cat > escrow/apps.py <<'ESAPPS'
from django.apps import AppConfig


class EscrowConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "escrow"
ESAPPS

cat > escrow/models.py <<'ESMODELS'
from django.db import models
from accounts.models import CustomUser
from marketplace.models import Order


class Escrow(models.Model):
    """Holds buyer funds until delivery is confirmed (Module 5).

    Lifecycle: pending -> held -> released (or refunded / disputed).
    """

    STATUS_CHOICES = [
        ("pending", "Pending funding"),
        ("held", "Funds held"),
        ("released", "Released to seller"),
        ("refunded", "Refunded to buyer"),
        ("disputed", "Disputed"),
    ]

    order = models.OneToOneField(
        Order, on_delete=models.CASCADE, related_name="escrow"
    )
    buyer = models.ForeignKey(
        CustomUser, on_delete=models.CASCADE, related_name="escrows"
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="USD")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="pending")
    funded_at = models.DateTimeField(blank=True, null=True)
    released_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Escrow #{self.pk} ({self.status}) - {self.amount}{self.currency}"
ESMODELS

cat > escrow/admin.py <<'ESADMIN'
from django.contrib import admin
from escrow.models import Escrow

admin.site.register(Escrow)
ESADMIN

cat > escrow/api/serializers.py <<'ESSER'
from rest_framework import serializers
from escrow.models import Escrow


class EscrowSerializer(serializers.ModelSerializer):
    class Meta:
        model = Escrow
        fields = "__all__"
        extra_kwargs = {
            "buyer": {"read_only": True},
            "funded_at": {"read_only": True},
            "released_at": {"read_only": True},
        }
ESSER

cat > escrow/api/views.py <<'ESVIEWS'
from django.db.models import Q
from django.utils import timezone
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from escrow.models import Escrow
from .serializers import EscrowSerializer


class EscrowViewSet(viewsets.ModelViewSet):
    queryset = Escrow.objects.all()
    serializer_class = EscrowSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        # Visible to the buyer and to the seller (store owner) on the order.
        user = self.request.user
        return Escrow.objects.filter(
            Q(buyer=user) | Q(order__store__owner=user)
        ).distinct()

    def perform_create(self, serializer):
        serializer.save(buyer=self.request.user)

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
        return Response(self.get_serializer(escrow).data)
ESVIEWS

# ---------------------------------------------------------------------------
# Wire into settings.py (INSTALLED_APPS) and urls.py (routes) - idempotent
# ---------------------------------------------------------------------------
python3 - "$SETTINGS" "$URLS" <<'PYEDIT'
import sys

settings_path, urls_path = sys.argv[1], sys.argv[2]

# --- settings.py: INSTALLED_APPS ---
with open(settings_path) as f:
    s = f.read()

if "marketprices" not in s:
    anchor = "    'analytics.apps.AnalyticsConfig',\n]"
    addition = (
        "    'analytics.apps.AnalyticsConfig',\n"
        "\n"
        "    # African Agricultural Commerce Ecosystem - Phase 1\n"
        "    'marketprices.apps.MarketPricesConfig',\n"
        "    'logistics.apps.LogisticsConfig',\n"
        "    'escrow.apps.EscrowConfig',\n"
        "]"
    )
    if anchor in s:
        s = s.replace(anchor, addition, 1)
        with open(settings_path, "w") as f:
            f.write(s)
        print("settings.py: registered marketprices, logistics, escrow")
    else:
        print("WARNING: INSTALLED_APPS anchor not found - add the 3 apps manually")
else:
    print("settings.py: apps already registered, skipping")

# --- urls.py: imports + router registrations ---
with open(urls_path) as f:
    u = f.read()

if "MarketPriceViewSet" not in u:
    imports = (
        "from marketprices.api.views import MarketPriceViewSet\n"
        "from logistics.api.views import (\n"
        "    VehicleViewSet,\n"
        "    TransportRequestViewSet,\n"
        "    TransportBidViewSet,\n"
        ")\n"
        "from escrow.api.views import EscrowViewSet\n\n"
        "router = DefaultRouter()"
    )
    if "router = DefaultRouter()" in u:
        u = u.replace("router = DefaultRouter()", imports, 1)

    regs_anchor = "router.register(r'reports', ReportViewSet, basename='report')"
    regs = (
        regs_anchor + "\n\n"
        "# Ecosystem - Phase 1\n"
        "router.register(r'market-prices', MarketPriceViewSet, basename='marketprice')\n"
        "router.register(r'vehicles', VehicleViewSet, basename='vehicle')\n"
        "router.register(r'transport-requests', TransportRequestViewSet, basename='transportrequest')\n"
        "router.register(r'transport-bids', TransportBidViewSet, basename='transportbid')\n"
        "router.register(r'escrows', EscrowViewSet, basename='escrow')"
    )
    if regs_anchor in u:
        u = u.replace(regs_anchor, regs, 1)

    with open(urls_path, "w") as f:
        f.write(u)
    print("urls.py: wired imports and 5 new routes")
else:
    print("urls.py: routes already present, skipping")
PYEDIT

echo ""
echo "Done. New apps created: marketprices, logistics, escrow"
echo ""
echo "Next steps:"
echo "  1. python manage.py makemigrations marketprices logistics escrow"
echo "  2. python manage.py migrate"
echo ""
echo "New endpoints (all under /api/):"
echo "  /api/market-prices/        (filters: ?commodity= &country= &price_type=)"
echo "  /api/vehicles/"
echo "  /api/transport-requests/"
echo "  /api/transport-bids/"
echo "  /api/escrows/   + POST /api/escrows/{id}/fund/  and  /release/"
echo ""
echo "Backups of settings.py and urls.py are in: $BACKUP_DIR/"
