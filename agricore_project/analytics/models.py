from django.db import models
from farms.models import Farm

class AnalyticsAggregate(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    period = models.CharField(max_length=20)
    metric_type = models.CharField(max_length=50)
    metric_value = models.DecimalField(max_digits=10, decimal_places=2)
    metadata = models.JSONField(default=dict)
    calculated_at = models.DateTimeField(auto_now_add=True)


# --- Farm Management Extensions ---
from accounts.models import CustomUser

class Expense(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='expenses')
    category = models.CharField(max_length=100)
    description = models.TextField(blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    date = models.DateField()
    created_by = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class Sale(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='sales')
    product = models.CharField(max_length=255)
    quantity = models.DecimalField(max_digits=12, decimal_places=2)
    unit = models.CharField(max_length=20)
    price_per_unit = models.DecimalField(max_digits=12, decimal_places=2)
    total_price = models.DecimalField(max_digits=14, decimal_places=2)
    buyer = models.CharField(max_length=255, blank=True)
    date = models.DateField()
    created_by = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class ActivityLog(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='activity_logs')
    user = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True)
    action = models.CharField(max_length=255)
    details = models.TextField(blank=True)
    timestamp = models.DateTimeField(auto_now_add=True)

class Report(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    report_type = models.CharField(max_length=50)
    parameters = models.JSONField(default=dict)
    generated_data = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)
    generated_at = models.DateTimeField(auto_now=True)

class FarmFinance(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    type = models.CharField(max_length=20)
    category = models.CharField(max_length=50)
    related_id = models.IntegerField(blank=True, null=True)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=3, default='USD')
    description = models.TextField(blank=True)
    date = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)