from django.db import models
from farms.models import Farm

class Employee(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='employees')
    first_name = models.CharField(max_length=100)
    last_name = models.CharField(max_length=100)
    phone = models.CharField(max_length=15)
    country_code = models.CharField(max_length=5)
    role = models.CharField(max_length=50)
    employment_type = models.CharField(max_length=50)
    hire_date = models.DateField()
    salary = models.DecimalField(max_digits=10, decimal_places=2)
    additional_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.first_name} {self.last_name} ({self.role})"

    class Meta:
        ordering = ['first_name', 'last_name']

class Machinery(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    name = models.CharField(max_length=255)
    type = models.CharField(max_length=50)
    description = models.TextField(blank=True)
    assigned_to = models.ForeignKey(Employee, related_name='assigned_machinery', on_delete=models.SET_NULL, null=True, blank=True)
    purchased_by = models.ForeignKey(Employee, related_name='purchased_machinery', on_delete=models.SET_NULL, null=True, blank=True)
    purchased_on = models.DateField(blank=True, null=True)
    value = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=50)
    created_at = models.DateTimeField(auto_now_add=True)

class Equipment(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    name = models.CharField(max_length=255)
    type = models.CharField(max_length=50)
    description = models.TextField(blank=True)
    assigned_to = models.ForeignKey(Employee, related_name='assigned_equipment', on_delete=models.SET_NULL, null=True, blank=True)
    purchased_by = models.ForeignKey(Employee, related_name='purchased_equipment', on_delete=models.SET_NULL, null=True, blank=True)
    purchased_on = models.DateField(blank=True, null=True)
    value = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=50)
    created_at = models.DateTimeField(auto_now_add=True)

class EmployeePerformance(models.Model):
    employee = models.ForeignKey(Employee, on_delete=models.CASCADE, related_name='performance_records')
    skillset = models.CharField(max_length=100)
    performance_rating = models.CharField(max_length=50)
    review_notes = models.TextField(blank=True)
    reviewed_at = models.DateTimeField()
    ai_recommendation = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['reviewed_at']

class FiredEmployee(models.Model):
    employee_id = models.IntegerField()
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='fired_employees')
    reason = models.TextField()
    fired_at = models.DateTimeField()
    rehired = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['fired_at']