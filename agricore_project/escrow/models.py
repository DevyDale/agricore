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


class PaymentTransaction(models.Model):
    """Audit record for every money movement tied to an escrow."""

    KIND_CHOICES = [
        ("collection", "Collection (buyer -> platform)"),
        ("payout", "Payout (platform -> seller)"),
    ]
    STATUS_CHOICES = [
        ("pending", "Pending"),
        ("successful", "Successful"),
        ("failed", "Failed"),
    ]

    escrow = models.ForeignKey(
        Escrow, on_delete=models.CASCADE, related_name="transactions"
    )
    kind = models.CharField(max_length=20, choices=KIND_CHOICES, default="collection")
    tx_ref = models.CharField(max_length=100, unique=True)
    flw_id = models.CharField(max_length=64, blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    fee = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    currency = models.CharField(max_length=3, default="UGX")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="pending")
    checkout_link = models.URLField(blank=True)
    raw = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.kind} {self.tx_ref} ({self.status})"
