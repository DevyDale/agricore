from django.db import models


class WeatherSnapshot(models.Model):
    """Latest cached weather for a farm (one row per farm, refreshed in place)."""

    farm = models.OneToOneField(
        "farms.Farm", on_delete=models.CASCADE, related_name="weather"
    )
    latitude = models.DecimalField(max_digits=9, decimal_places=5, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=5, null=True, blank=True)
    location_name = models.CharField(max_length=255, blank=True)
    data = models.JSONField(default=dict, blank=True)
    fetched_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-fetched_at"]

    def __str__(self):
        return f"Weather for farm {self.farm_id} ({self.location_name or 'unknown'})"
