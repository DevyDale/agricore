
from django.db import models
from farms.models import Field
from workforce.models import Employee
from accounts.models import Attachment

# --- Unified Event and Production Models ---

class LivestockEvent(models.Model):
    EVENT_TYPE_CHOICES = [
        ("health", "Health Event"),
        ("breeding", "Breeding Event"),
        ("movement", "Movement"),
        ("mortality", "Mortality"),
        ("treatment", "Treatment"),
        ("inspection", "Inspection"),
        ("feeding", "Feeding"),
        ("harvest", "Harvest"),
        ("other", "Other"),
    ]
    livestock_unit = models.ForeignKey('LivestockUnit', on_delete=models.CASCADE)
    event_type = models.CharField(max_length=30, choices=EVENT_TYPE_CHOICES)
    event_date = models.DateField()
    description = models.TextField(blank=True)
    quantity = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.get_event_type_display()} for {self.livestock_unit} on {self.event_date}"

class ProductionRecord(models.Model):
    livestock_unit = models.ForeignKey('LivestockUnit', on_delete=models.CASCADE, related_name='livestock_production_records')
    product_name = models.CharField(max_length=100)
    quantity = models.DecimalField(max_digits=10, decimal_places=2)
    unit = models.CharField(max_length=20)
    record_date = models.DateField()
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.quantity} {self.unit} {self.product_name} from {self.livestock_unit} on {self.record_date}"

class LivestockUnit(models.Model):
    UNIT_TYPE_CHOICES = [
        ("individual", "Individual Animal"),
        ("herd", "Herd"),
        ("batch", "Batch/Stock"),
        ("colony", "Colony/Hive"),
        ("population", "Population/Culture"),
    ]
    field = models.ForeignKey(Field, on_delete=models.CASCADE, blank=True, null=True)
    unit_name = models.CharField(max_length=255)
    unit_type = models.CharField(max_length=20, choices=UNIT_TYPE_CHOICES, blank=True, null=True)
    species = models.CharField(max_length=100, blank=True, null=True)
    breed = models.CharField(max_length=255, blank=True)
    quantity = models.IntegerField(blank=True, null=True)
    location = models.CharField(max_length=255, blank=True)
    # Batch/Colony/Population specific fields
    installation_date = models.DateField(blank=True, null=True)  # For hives, batches, etc.
    housing = models.CharField(max_length=100, blank=True)  # Coop, pen, pond, etc.
    queen_status = models.CharField(max_length=50, blank=True)  # For bees
    average_weight = models.DecimalField(max_digits=8, decimal_places=2, blank=True, null=True)  # For herds
    from django.contrib.postgres.fields import ArrayField
    purpose = ArrayField(
        models.CharField(max_length=100, blank=True),
        blank=True,
        default=list,
        help_text='List of purposes, e.g. ["meat", "milk"]'
    )
    sub_units = models.JSONField(blank=True, null=True, help_text='List of sub-units with count, age_range, stage, etc.')
    # --- Produce fields ---
    produce_type = models.CharField(max_length=100, blank=True, null=True, help_text='Type of produce, e.g. Milk, Eggs, Honey')
    produce_frequency = models.CharField(max_length=20, blank=True, null=True, help_text='Frequency: Per Day, Per Week, etc.')
    produce_quantity = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True, help_text='Quantity per frequency')
    produce_unit = models.CharField(max_length=20, blank=True, null=True, help_text='Unit, e.g. liters, kg, pieces')
    additional_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.unit_name} ({self.get_unit_type_display()})"

class Animal(models.Model):
    """
    Only used for unit_type = 'individual'.
    """
    livestock_unit = models.ForeignKey(LivestockUnit, on_delete=models.CASCADE, limit_choices_to={"unit_type": "individual"})
    tag_id = models.CharField(max_length=50)
    name = models.CharField(max_length=255, blank=True)
    sex = models.CharField(max_length=10)
    age_group = models.CharField(max_length=20, blank=True)
    dob = models.DateField(blank=True, null=True)
    breed = models.CharField(max_length=255, blank=True)
    status = models.CharField(max_length=50)
    health_score = models.DecimalField(max_digits=5, decimal_places=2, blank=True, null=True)
    father = models.ForeignKey('self', related_name='father_children', on_delete=models.SET_NULL, null=True, blank=True)
    mother = models.ForeignKey('self', related_name='mother_children', on_delete=models.SET_NULL, null=True, blank=True)
    value_estimate = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    additional_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.tag_id} ({self.name})"

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
