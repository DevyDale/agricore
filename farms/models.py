from django.db import models
from accounts.models import CustomUser

class Farm(models.Model):
    owner = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    name = models.CharField(max_length=255)
    type = models.CharField(max_length=50)
    country = models.CharField(max_length=100)
    state = models.CharField(max_length=100)
    city = models.CharField(max_length=100)
    address = models.CharField(max_length=255)
    total_size = models.DecimalField(max_digits=10, decimal_places=2)
    size_unit = models.CharField(max_length=20)
    last_visited = models.DateTimeField(blank=True, null=True)
    additional_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class Field(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    name = models.CharField(max_length=255)
    purpose = models.CharField(max_length=50)
    total_size = models.DecimalField(max_digits=10, decimal_places=2)
    size_unit = models.CharField(max_length=20)
    soil_type = models.CharField(max_length=50)
    additional_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class EnvironmentalData(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    date = models.DateField()
    temperature = models.DecimalField(max_digits=5, decimal_places=2, blank=True, null=True)
    rainfall = models.DecimalField(max_digits=5, decimal_places=2, blank=True, null=True)
    humidity = models.DecimalField(max_digits=5, decimal_places=2, blank=True, null=True)
    soil_moisture = models.DecimalField(max_digits=5, decimal_places=2, blank=True, null=True)
    pest_alerts = models.TextField(blank=True)
    additional_info = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)