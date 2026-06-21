from django.db import models

from marketplace.models import Order


class PesapalPayment(models.Model):
    """One Pesapal checkout attempt for a marketplace Order.

    Records the merchant reference we generated, the Pesapal tracking id, and the
    last known status so the callback/IPN can find the order again and so
    fulfilment runs exactly once. Keeping this in its own model means the
    marketplace app's Order doesn't have to change.
    """

    STATUS_CHOICES = [
        ("PENDING", "Pending"),
        ("COMPLETED", "Completed"),
        ("FAILED", "Failed"),
        ("REVERSED", "Reversed"),
        ("INVALID", "Invalid"),
    ]

    order = models.ForeignKey(
        Order, on_delete=models.CASCADE, related_name="pesapal_payments"
    )
    # Our unique reference for this attempt (Pesapal's "id" field).
    merchant_ref = models.CharField(max_length=100, unique=True)
    # Pesapal's id for the transaction; the callback + IPN look the order up by this.
    order_tracking_id = models.CharField(max_length=64, blank=True, db_index=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="UGX")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="PENDING")
    redirect_url = models.URLField(blank=True)
    raw = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Pesapal {self.merchant_ref} ({self.status})"
