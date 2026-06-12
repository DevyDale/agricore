from django.db import models


class MarketPrice(models.Model):
    """Reference commodity prices by country/region (Module 2)."""

    PRICE_TYPE_CHOICES = [
        ("local", "Local"),
        ("regional", "Regional"),
        ("export", "Export"),
    ]

    CATEGORY_CHOICES = [
        ("crop", "Crop"),
        ("livestock", "Livestock"),
        ("input", "Input"),
    ]

    commodity = models.CharField(max_length=100)            # e.g. "Maize"
    variety = models.CharField(max_length=100, blank=True)
    country = models.CharField(max_length=100)
    region = models.CharField(max_length=100, blank=True)
    price_type = models.CharField(
        max_length=20, choices=PRICE_TYPE_CHOICES, default="local"
    )
    category = models.CharField(
        max_length=20, choices=CATEGORY_CHOICES, default="crop"
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
