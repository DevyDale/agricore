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
    # ---- Verified Trade Chain v1: delivery verification + dispute window ----
    delivery_otp = models.CharField(max_length=8, blank=True, default="")
    otp_issued_at = models.DateTimeField(blank=True, null=True)
    delivered_confirmed_at = models.DateTimeField(blank=True, null=True)
    dispute_deadline = models.DateTimeField(blank=True, null=True)
    dispute_reason = models.TextField(blank=True, default="")
    # ---- Proof of condition: photos + recorded quantity at dispatch and dispute ----
    dispatch_quantity = models.CharField(max_length=120, blank=True, default="")
    dispatch_note = models.TextField(blank=True, default="")
    dispatch_photo = models.ImageField(upload_to="trade_proof/", blank=True, null=True)
    dispute_quantity = models.CharField(max_length=120, blank=True, default="")
    dispute_photo = models.ImageField(upload_to="trade_proof/", blank=True, null=True)
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


class PayoutAccount(models.Model):
    """Where a seller receives their money (mobile money or bank)."""

    METHOD_CHOICES = [("momo", "Mobile Money"), ("bank", "Bank")]

    user = models.OneToOneField(
        CustomUser, on_delete=models.CASCADE, related_name="payout_account"
    )
    method = models.CharField(max_length=10, choices=METHOD_CHOICES, default="momo")
    account_bank = models.CharField(
        max_length=20, default="MPS",
        help_text='"MPS" for mobile money, or a bank code for bank payouts',
    )
    account_number = models.CharField(
        max_length=40,
        help_text="Mobile number (international format) for MoMo, or bank account number",
    )
    account_name = models.CharField(max_length=120)
    network = models.CharField(
        max_length=20, blank=True, help_text="MTN or AIRTEL (mobile money only)"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Payout for {self.user} ({self.method})"
