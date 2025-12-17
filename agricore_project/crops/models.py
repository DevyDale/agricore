from django.db import models
from farms.models import Field
from workforce.models import Employee
from accounts.models import Attachment

class Crop(models.Model):
    field = models.ForeignKey(Field, on_delete=models.CASCADE)
    name = models.CharField(max_length=255)
    variety = models.CharField(max_length=255)
    seed_source = models.CharField(max_length=255)
    planting_month_year = models.CharField(max_length=20)
    expected_harvest_month_year = models.CharField(max_length=20)
    status = models.CharField(max_length=50)
    yield_estimate = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    yield_unit = models.CharField(max_length=20, blank=True)
    value_estimate = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    additional_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class CropTask(models.Model):
    crop = models.ForeignKey(Crop, on_delete=models.CASCADE)
    title = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    start_date = models.DateField()
    due_date = models.DateField()
    status = models.CharField(max_length=50)
    equipment_used = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(blank=True, null=True)

class CropEmployeeAssignment(models.Model):
    crop_task = models.ForeignKey(CropTask, on_delete=models.CASCADE)
    employee = models.ForeignKey(Employee, on_delete=models.CASCADE)
    role = models.CharField(max_length=50)
    assigned_at = models.DateTimeField(auto_now_add=True)
    removed_at = models.DateTimeField(blank=True, null=True)
    ai_recommended_duration = models.IntegerField(blank=True, null=True)

class CropExpense(models.Model):
    crop = models.ForeignKey(Crop, on_delete=models.CASCADE)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=3, default='USD')
    category = models.CharField(max_length=50)
    additional_notes = models.TextField(blank=True)
    purchased_by = models.ForeignKey(Employee, on_delete=models.SET_NULL, null=True, blank=True)
    receipt_attachment = models.ForeignKey(Attachment, on_delete=models.SET_NULL, null=True, blank=True)
    incurred_on = models.DateField()
    created_at = models.DateTimeField(auto_now_add=True)