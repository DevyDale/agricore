from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from .models import Farm, Field
from .api.serializers import FarmSerializer, FieldSerializer

@receiver(post_save, sender=Farm)
@receiver(post_delete, sender=Farm)
def broadcast_farm_update(sender, instance, **kwargs):
    channel_layer = get_channel_layer()
    if kwargs.get('created', False):
        data = FarmSerializer(instance).data
    else:
        data = {'id': instance.id, 'deleted': post_delete == sender}  # Fixed
    async_to_sync(channel_layer.group_send)(
        f'farm_{instance.id}',
        {'type': 'model.update', 'model': 'farm', 'data': data}
    )

@receiver(post_save, sender=Field)
@receiver(post_delete, sender=Field)
def broadcast_field_update(sender, instance, **kwargs):
    channel_layer = get_channel_layer()
    if kwargs.get('created', False):
        data = FieldSerializer(instance).data
    else:
        data = {'id': instance.id, 'deleted': post_delete == sender}
    async_to_sync(channel_layer.group_send)(
        f'farm_{instance.farm.id}',
        {'type': 'model.update', 'model': 'field', 'data': data}
    )