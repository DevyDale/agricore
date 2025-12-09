from django.db import models
from farms.models import Farm

class AnalyticsAggregate(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    period = models.CharField(max_length=20)
    metric_type = models.CharField(max_length=50)
    metric_value = models.DecimalField(max_digits=10, decimal_places=2)
    metadata = models.JSONField(default=dict)
    calculated_at = models.DateTimeField(auto_now_add=True)

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