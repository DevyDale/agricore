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


# ===== Verified Trade Chain: transporter subsystem (self-contained) =====
from django.db import models
from accounts.models import CustomUser
from marketplace.models import Order
from escrow.models import Escrow


class Transporter(models.Model):
    """A registered rider/driver who delivers orders (boda, pickup, truck, taxi)."""
    VEHICLE_CHOICES = [
        ("boda", "Boda boda (motorcycle)"),
        ("pickup", "Pickup"),
        ("truck", "Truck"),
        ("taxi", "Taxi / van"),
        ("bicycle", "Bicycle"),
    ]
    user = models.OneToOneField(CustomUser, on_delete=models.CASCADE, related_name="transporter")
    vehicle_type = models.CharField(max_length=20, choices=VEHICLE_CHOICES, default="boda")
    vehicle_plate = models.CharField(max_length=30, blank=True, default="")
    national_id = models.CharField(max_length=40, blank=True, default="")
    phone = models.CharField(max_length=32, blank=True, default="")
    service_area = models.CharField(max_length=160, blank=True, default="", help_text="Districts/areas served")
    is_verified = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    rating_avg = models.DecimalField(max_digits=3, decimal_places=2, default=0)
    rating_count = models.PositiveIntegerField(default=0)
    deposit_required = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    deposit_balance = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    photo = models.ImageField(upload_to="transporters/", blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Transporter {self.user} ({self.vehicle_type})"


class DeliveryJob(models.Model):
    """A delivery assignment for an order, carried by a transporter."""
    STATUS_CHOICES = [
        ("open", "Open (awaiting a rider)"),
        ("accepted", "Accepted"),
        ("picked_up", "Picked up"),
        ("delivered", "Delivered"),
        ("cancelled", "Cancelled"),
    ]
    order = models.OneToOneField(Order, on_delete=models.CASCADE, related_name="delivery_job")
    escrow = models.ForeignKey(Escrow, on_delete=models.SET_NULL, null=True, blank=True, related_name="delivery_jobs")
    created_by = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name="created_delivery_jobs")
    transporter = models.ForeignKey(Transporter, on_delete=models.SET_NULL, null=True, blank=True, related_name="jobs")
    vehicle_type_required = models.CharField(max_length=20, blank=True, default="")
    pickup_location = models.CharField(max_length=255, blank=True, default="")
    drop_location = models.CharField(max_length=255, blank=True, default="")
    offered_fee = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    currency = models.CharField(max_length=3, default="UGX")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="open")
    pickup_code = models.CharField(max_length=8, blank=True, default="")
    notes = models.TextField(blank=True, default="")
    # ---- App-less rider one-time link (Phase 3): token-authorised, no login ----
    access_token = models.CharField(max_length=64, blank=True, default="", db_index=True)
    access_phone = models.CharField(max_length=20, blank=True, default="")
    access_name = models.CharField(max_length=120, blank=True, default="")
    accepted_at = models.DateTimeField(blank=True, null=True)
    picked_up_at = models.DateTimeField(blank=True, null=True)
    delivered_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"DeliveryJob #{self.pk} order={self.order_id} ({self.status})"


class TransporterReview(models.Model):
    transporter = models.ForeignKey(Transporter, on_delete=models.CASCADE, related_name="reviews")
    order = models.ForeignKey(Order, on_delete=models.SET_NULL, null=True, blank=True)
    by_user = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name="transporter_reviews")
    rating = models.PositiveSmallIntegerField(default=5)
    comment = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Review {self.rating}* for {self.transporter_id}"
