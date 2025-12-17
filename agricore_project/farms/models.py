# farms/models.py
from django.db import models
from accounts.models import CustomUser


class Farm(models.Model):
    owner = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name='farms', null=True, blank=True)
    name = models.CharField(max_length=255, null=True, blank=True)
    type = models.CharField(
        max_length=20,
        choices=[('crops', 'Crops'), ('livestock', 'Livestock'), ('mixed', 'Mixed')],
        default='crops',
        null=True,
        blank=True
    )
    country = models.CharField(max_length=100, null=True, blank=True)
    state = models.CharField(max_length=100, null=True, blank=True)
    city = models.CharField(max_length=100, null=True, blank=True)
    address = models.CharField(max_length=255, blank=True, null=True)
    total_size = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    size_unit = models.CharField(
            max_length=20,
            choices=[('acres', 'Acres'), ('hectares', 'Hectares'), ('square_meters', 'Square Meters')],
            default='acres',
            null=True,
            blank=True
        )
    additional_notes = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True, null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True, null=True, blank=True)

    def __str__(self):
        return f"{self.name} - {self.owner.username}"


class Field(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='fields', null=True, blank=True)
    name = models.CharField(max_length=255, null=True, blank=True)
    purpose = models.CharField(max_length=50, blank=True, null=True)
    total_size = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    size_unit = models.CharField(
        max_length=20,
        choices=[('acres','Acres'),('hectares','Hectares'),('square_meters','Square Meters')],
        default='acres',
        null=True,
        blank=True
    )
    soil_type = models.CharField(max_length=50, blank=True, null=True)
    additional_notes = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True, null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True, null=True, blank=True)


class EnvironmentalData(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='environmental_data', null=True, blank=True)
    date = models.DateField(null=True, blank=True)
    temperature = models.DecimalField(max_digits=5, decimal_places=2, blank=True, null=True)
    rainfall = models.DecimalField(max_digits=5, decimal_places=2, blank=True, null=True)
    humidity = models.DecimalField(max_digits=5, decimal_places=2, blank=True, null=True)
    soil_moisture = models.DecimalField(max_digits=5, decimal_places=2, blank=True, null=True)
    pest_alerts = models.TextField(blank=True, null=True)
    additional_info = models.JSONField(default=dict, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True, null=True, blank=True)