from django.db import models
from farms.models import Field
from workforce.models import Employee
from accounts.models import Attachment

class LivestockUnit(models.Model):
    field = models.ForeignKey(Field, on_delete=models.CASCADE)
    unit_name = models.CharField(max_length=255)
    animal_type = models.CharField(max_length=50)
    quantity = models.IntegerField()
    breed = models.CharField(max_length=255)
    additional_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class Animal(models.Model):
    livestock_unit = models.ForeignKey(LivestockUnit, on_delete=models.CASCADE)
    tag_id = models.CharField(max_length=50)
    name = models.CharField(max_length=255, blank=True)
    sex = models.CharField(max_length=10)
    age_group = models.CharField(max_length=20)
    dob = models.DateField(blank=True, null=True)
    breed = models.CharField(max_length=255)
    status = models.CharField(max_length=50)
    health_score = models.DecimalField(max_digits=5, decimal_places=2, blank=True, null=True)
    father = models.ForeignKey('self', related_name='father_children', on_delete=models.SET_NULL, null=True, blank=True)
    mother = models.ForeignKey('self', related_name='mother_children', on_delete=models.SET_NULL, null=True, blank=True)
    value_estimate = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    additional_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class AnimalReproductiveRecord(models.Model):
    animal = models.ForeignKey(Animal, on_delete=models.CASCADE)
    sex = models.CharField(max_length=10)
    event_date = models.DateField()
    event_type = models.CharField(max_length=50)
    details = models.TextField(blank=True)
    offspring_ids = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

class LivestockTask(models.Model):
    livestock_unit = models.ForeignKey(LivestockUnit, on_delete=models.CASCADE)
    title = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    start_date = models.DateField()
    due_date = models.DateField()
    status = models.CharField(max_length=50)
    equipment_used = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(blank=True, null=True)

class LivestockEmployeeAssignment(models.Model):
    livestock_task = models.ForeignKey(LivestockTask, on_delete=models.CASCADE)
    employee = models.ForeignKey(Employee, on_delete=models.CASCADE)
    role = models.CharField(max_length=50)
    assigned_at = models.DateTimeField(auto_now_add=True)
    removed_at = models.DateTimeField(blank=True, null=True)
    ai_recommended_duration = models.IntegerField(blank=True, null=True)

class LivestockExpense(models.Model):
    livestock_unit = models.ForeignKey(LivestockUnit, on_delete=models.CASCADE)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=3, default='USD')
    category = models.CharField(max_length=50)
    additional_notes = models.TextField(blank=True)
    purchased_by = models.ForeignKey(Employee, on_delete=models.SET_NULL, null=True, blank=True)
    receipt_attachment = models.ForeignKey(Attachment, on_delete=models.SET_NULL, null=True, blank=True)
    incurred_on = models.DateField()
    created_at = models.DateTimeField(auto_now_add=True)

class AnimalMedicalRecord(models.Model):
    animal = models.ForeignKey(Animal, on_delete=models.CASCADE)
    livestock_unit = models.ForeignKey(LivestockUnit, on_delete=models.CASCADE)
    date = models.DateField()
    record_type = models.CharField(max_length=50)
    drug_name = models.CharField(max_length=255, blank=True)
    quantity_used = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    next_vaccination_date = models.DateField(blank=True, null=True)
    veterinarian = models.ForeignKey('accounts.SpecializedProfessional', on_delete=models.SET_NULL, null=True, blank=True)
    cost = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    additional_info = models.TextField(blank=True)
    attachment = models.ForeignKey(Attachment, on_delete=models.SET_NULL, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
