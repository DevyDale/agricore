from django.db import models
from farms.models import Farm
from crops.models import Crop
from livestock.models import Animal, LivestockUnit

class Inventory(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    item_name = models.CharField(max_length=255)
    category = models.CharField(max_length=50)
    quantity = models.DecimalField(max_digits=10, decimal_places=2)
    unit = models.CharField(max_length=20)
    reorder_threshold = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    supplier = models.CharField(max_length=255, blank=True)
    last_received_date = models.DateField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class ProductionRecord(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    crop = models.ForeignKey(Crop, on_delete=models.SET_NULL, null=True, blank=True)
    animal = models.ForeignKey(Animal, on_delete=models.SET_NULL, null=True, blank=True)
    livestock_unit = models.ForeignKey(LivestockUnit, on_delete=models.SET_NULL, null=True, blank=True)
    date = models.DateField()
    item_type = models.CharField(max_length=50)
    quantity = models.DecimalField(max_digits=10, decimal_places=2)
    unit = models.CharField(max_length=20)
    value_estimate = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)