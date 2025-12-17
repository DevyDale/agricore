# # farms/signals.py
# from django.db.models.signals import post_save, post_delete
# from django.dispatch import receiver
# from asgiref.sync import async_to_sync
# from channels.layers import get_channel_layer
# from .models import Farm, Field
# from .api.serializers import FarmSerializer, FieldSerializer


# @receiver([post_save, post_delete], sender=Farm)
# def broadcast_farm_update(sender, instance, **kwargs):
#     channel_layer = get_channel_layer()
#     if channel_layer is None:
#         return

#     if sender is post_save:
#         data = FarmSerializer(instance).data
#         deleted = False
#     else:
#         data = {'id': instance.id}
#         deleted = True

#     async_to_sync(channel_layer.group_send)(
#         f'farm_{instance.id}',
#         {
#             'type': 'model.update',
#             'model': 'farm',
#             'action': 'created' if not deleted else 'deleted',
#             'data': data
#         }
#     )


# @receiver([post_save, post_delete], sender=Field)
# def broadcast_field_update(sender, instance, **kwargs):
#     channel_layer = get_channel_layer()
#     if channel_layer is None:
#         return

#     if sender is post_save:
#         data = FieldSerializer(instance).data
#         deleted = False
#     else:
#         data = {'id': instance.id}
#         deleted = True

#     async_to_sync(channel_layer.group_send)(
#         f'farm_{instance.farm.id}',
#         {
#             'type': 'model.update',
#             'model': 'field',
#             'action': 'created' if not deleted else 'deleted',
#             'data': data
#         }
#     )