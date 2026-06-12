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
