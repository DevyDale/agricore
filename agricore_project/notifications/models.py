from django.conf import settings
from django.db import models


class Notification(models.Model):
    CATEGORY_CHOICES = [
        ("order", "Order"),
        ("payment", "Payment"),
        ("escrow", "Escrow"),
        ("task", "Task"),
        ("message", "Message"),
        ("logistics", "Logistics"),
        ("system", "System"),
    ]

    recipient = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications"
    )
    category = models.CharField(max_length=20, choices=CATEGORY_CHOICES, default="system")
    title = models.CharField(max_length=255)
    body = models.TextField(blank=True)
    related_table = models.CharField(max_length=50, blank=True)
    related_id = models.IntegerField(null=True, blank=True)
    url = models.CharField(max_length=500, blank=True)  # frontend deep link
    is_read = models.BooleanField(default=False)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["recipient", "is_read"])]

    def __str__(self):
        return f"[{self.category}] {self.title} -> {self.recipient_id}"
