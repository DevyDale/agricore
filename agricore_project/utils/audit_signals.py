from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from django.contrib.contenttypes.models import ContentType
from utils.models import AuditLog
from django.conf import settings
from django.contrib.auth import get_user_model
import json

# List of models to audit
from farms.models import Farm, Field
from livestock.models import LivestockUnit, Animal
# from crops.models import Crop  # Removed: Crop model deprecated
from analytics.models import Expense, Sale, ActivityLog

MODELS_TO_AUDIT = [Farm, Field, LivestockUnit, Animal, Expense, Sale, ActivityLog]

# Helper to get changed fields

def get_changes(instance):
    if not instance.pk:
        return {}
    try:
        old = instance.__class__.objects.get(pk=instance.pk)
    except instance.__class__.DoesNotExist:
        return {}
    changes = {}
    for field in instance._meta.fields:
        name = field.name
        old_val = getattr(old, name)
        new_val = getattr(instance, name)
        if old_val != new_val:
            changes[name] = {'old': old_val, 'new': new_val}
    return changes

for model in MODELS_TO_AUDIT:
    @receiver(post_save, sender=model)
    def audit_save(sender, instance, created, **kwargs):
        user = getattr(instance, 'created_by', None) or getattr(instance, 'user', None)
        AuditLog.objects.create(
            user=user if isinstance(user, get_user_model()) else None,
            content_type=ContentType.objects.get_for_model(sender),
            object_id=instance.pk,
            action='created' if created else 'updated',
            changes=get_changes(instance) if not created else {},
        )

    @receiver(post_delete, sender=model)
    def audit_delete(sender, instance, **kwargs):
        user = getattr(instance, 'created_by', None) or getattr(instance, 'user', None)
        AuditLog.objects.create(
            user=user if isinstance(user, get_user_model()) else None,
            content_type=ContentType.objects.get_for_model(sender),
            object_id=instance.pk,
            action='deleted',
            changes={},
        )
