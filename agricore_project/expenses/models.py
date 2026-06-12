from django.db import models
from farms.models import Farm, Field
from crops.models import CropUnit, CropCycle
from livestock.models import LivestockUnit, Animal
from workforce.models import Employee
from django.contrib.contenttypes.fields import GenericForeignKey
from django.contrib.contenttypes.models import ContentType

class ExpenseCategory(models.Model):
    CATEGORY_CHOICES = [
        ("input", "Input"),
        ("labor", "Labor"),
        ("equipment", "Equipment & Maintenance"),
        ("utilities", "Utilities"),
        ("overhead", "Overhead/Miscellaneous"),
    ]
    name = models.CharField(max_length=50, choices=CATEGORY_CHOICES, unique=True)
    description = models.CharField(max_length=255, blank=True)

    def __str__(self):
        return self.get_name_display()

class Expense(models.Model):
    category = models.ForeignKey(ExpenseCategory, on_delete=models.PROTECT)
    name = models.CharField(max_length=100)
    quantity = models.DecimalField(max_digits=10, decimal_places=2)
    unit = models.CharField(max_length=30)
    unit_cost = models.DecimalField(max_digits=10, decimal_places=2)
    total_cost = models.DecimalField(max_digits=12, decimal_places=2)
    date = models.DateField()
    notes = models.TextField(blank=True)
    vendor = models.CharField(max_length=100, blank=True)
    payment_method = models.CharField(max_length=50, blank=True)
    # Link to any farm unit/activity (CropCycle, LivestockUnit, Animal, Field, etc.)
    content_type = models.ForeignKey(ContentType, on_delete=models.SET_NULL, null=True, blank=True)
    object_id = models.PositiveIntegerField(null=True, blank=True)
    linked_object = GenericForeignKey('content_type', 'object_id')
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    created_by = models.ForeignKey(Employee, on_delete=models.SET_NULL, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def save(self, *args, **kwargs):
        if not self.total_cost:
            self.total_cost = self.quantity * self.unit_cost
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.name} ({self.category}) - {self.total_cost}"

class ExpenseEvent(models.Model):
    expense = models.ForeignKey(Expense, on_delete=models.CASCADE, related_name='events')
    date = models.DateField()
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    notes = models.TextField(blank=True)
    is_recurring = models.BooleanField(default=False)
    recurrence_pattern = models.CharField(max_length=50, blank=True)  # e.g., weekly, monthly
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.expense} on {self.date}"

class Payment(models.Model):
    expense = models.ForeignKey(Expense, on_delete=models.CASCADE, related_name='payments')
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    date = models.DateField()
    status = models.CharField(max_length=20, choices=[('paid', 'Paid'), ('pending', 'Pending')], default='pending')
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.expense} - {self.amount} ({self.status})"
