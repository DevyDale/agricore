
from django.db import models
from farms.models import Field
from workforce.models import Employee
from accounts.models import Attachment


# --- Unified Crop Management Models ---

class CropUnit(models.Model):
    UNIT_TYPE_CHOICES = [
        ("field", "Field/Plot"),
        ("bed", "Bed/Plot"),
        ("greenhouse", "Greenhouse/Block"),
        ("orchard", "Orchard Block"),
        ("hydroponic", "Hydroponic System/Channel"),
    ]
    unit_name = models.CharField(max_length=255)
    unit_type = models.CharField(max_length=20, choices=UNIT_TYPE_CHOICES)
    field = models.ForeignKey(Field, on_delete=models.CASCADE, blank=True, null=True)
    # area field removed
    location = models.CharField(max_length=255, blank=True)
    additional_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.unit_name} ({self.get_unit_type_display()})"

class CropCycle(models.Model):
    crop_unit = models.ForeignKey(CropUnit, on_delete=models.CASCADE)
    crop_type = models.CharField(max_length=100)
    variety = models.CharField(max_length=100, blank=True)
    planting_method = models.CharField(max_length=50, blank=True)
    planting_date = models.DateField()
    expected_harvest_date = models.DateField(blank=True, null=True)
    # area field removed
    status = models.CharField(max_length=50, blank=True)
    additional_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.crop_type} – {self.crop_unit} – {self.planting_date.year}"

class CropEvent(models.Model):
    EVENT_TYPE_CHOICES = [
        ("planting", "Planting"),
        ("fertilizer", "Fertilizer Application"),
        ("irrigation", "Irrigation"),
        ("pesticide", "Pesticide/Herbicide"),
        ("mulching", "Mulching"),
        ("germination", "Germination Observation"),
        ("growth", "Growth Stage"),
        ("pest", "Pest/Disease Observation"),
        ("stress", "Stress Event"),
        ("harvest", "Harvest"),
        ("loss", "Crop Failure/Loss"),
        ("other", "Other"),
    ]
    crop_cycle = models.ForeignKey(CropCycle, on_delete=models.CASCADE)
    event_type = models.CharField(max_length=30, choices=EVENT_TYPE_CHOICES)
    event_date = models.DateField()
    description = models.TextField(blank=True)
    quantity = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    unit = models.CharField(max_length=20, blank=True)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.get_event_type_display()} for {self.crop_cycle} on {self.event_date}"

class HarvestRecord(models.Model):
    crop_cycle = models.ForeignKey(CropCycle, on_delete=models.CASCADE)
    harvest_date = models.DateField()
    product_name = models.CharField(max_length=100)
    quantity = models.DecimalField(max_digits=10, decimal_places=2)
    unit = models.CharField(max_length=20)
    quality_grade = models.CharField(max_length=100, blank=True, null=True)
    notes = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.quantity} {self.unit} {self.product_name} from {self.crop_cycle} on {self.harvest_date}"

# Deprecated: Old CropTask model (remove or refactor to use CropUnit/CropCycle)
# class CropTask(models.Model):
#     crop = models.ForeignKey(Crop, on_delete=models.CASCADE)
#     title = models.CharField(max_length=255)
#     description = models.TextField(blank=True)
#     start_date = models.DateField()
#     due_date = models.DateField()
#     status = models.CharField(max_length=50)
#     equipment_used = models.CharField(max_length=255, blank=True)
#     created_at = models.DateTimeField(auto_now_add=True)
#     completed_at = models.DateTimeField(blank=True, null=True)

# Deprecated: Old CropEmployeeAssignment model (remove or refactor to use new models)
# class CropEmployeeAssignment(models.Model):
#     crop_task = models.ForeignKey(CropTask, on_delete=models.CASCADE)
#     employee = models.ForeignKey(Employee, on_delete=models.CASCADE)
#     role = models.CharField(max_length=50)
#     assigned_at = models.DateTimeField(auto_now_add=True)
#     removed_at = models.DateTimeField(blank=True, null=True)
#     ai_recommended_duration = models.IntegerField(blank=True, null=True)

# Deprecated: Old CropExpense model (remove or refactor to use new models)
# class CropExpense(models.Model):
#     crop = models.ForeignKey(Crop, on_delete=models.CASCADE)
#     amount = models.DecimalField(max_digits=10, decimal_places=2)
#     currency = models.CharField(max_length=3, default='USD')
#     category = models.CharField(max_length=50)
#     additional_notes = models.TextField(blank=True)
#     purchased_by = models.ForeignKey(Employee, on_delete=models.SET_NULL, null=True, blank=True)
#     receipt_attachment = models.ForeignKey(Attachment, on_delete=models.SET_NULL, null=True, blank=True)
#     incurred_on = models.DateField()
#     created_at = models.DateTimeField(auto_now_add=True)