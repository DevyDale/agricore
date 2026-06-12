from django.db import models
from django.utils import timezone
from farms.models import Farm
## from crops.models import Crop  # Removed: Crop model deprecated
from accounts.models import CustomUser

# 🚨 IMPORTANT: If the SpecializedProfessional model is defined anywhere in this file (ai/models.py), 
# you MUST delete it entirely. It is causing the E304 clash.

class AILog(models.Model):
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    context_type = models.CharField(max_length=50)
    context_id = models.IntegerField()
    prompt = models.TextField()
    response = models.TextField()
    model = models.CharField(max_length=50)
    tokens_used = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, null=True, blank=True)
    # crop = models.ForeignKey(Crop, on_delete=models.CASCADE, null=True, blank=True)  # Removed
    livestock_unit = models.ForeignKey('livestock.LivestockUnit', on_delete=models.CASCADE, null=True, blank=True)
    animal = models.ForeignKey('livestock.Animal', on_delete=models.CASCADE, null=True, blank=True)
    prediction_type = models.CharField(max_length=50, default="")
    inputs = models.JSONField(default=dict)
    result = models.JSONField(default=dict)
    confidence = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    explanation = models.TextField(default="")
    generated_at = models.DateTimeField(default=timezone.now)

class Alert(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    type = models.CharField(max_length=50)
    title = models.CharField(max_length=255)
    message = models.TextField()
    related_table = models.CharField(max_length=50)
    related_id = models.IntegerField()
    due_date = models.DateTimeField(blank=True, null=True)
    sent_to_email = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    resolved = models.BooleanField(default=False)