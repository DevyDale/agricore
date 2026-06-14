from rest_framework import serializers
from ..models import CropCycle, CropUnit
from farms.models import Field


class CropCycleSerializer(serializers.ModelSerializer):
    # The form sends a land portion (Field) id. We accept it here and resolve
    # (or create) the CropUnit behind the scenes, so the user never has to deal
    # with units directly.
    field = serializers.PrimaryKeyRelatedField(
        queryset=Field.objects.all(), write_only=True, required=False
    )
    # Read-only helpers so the crops table can show the land portion name.
    field_name = serializers.SerializerMethodField(read_only=True)
    crop_unit_name = serializers.CharField(source='crop_unit.unit_name', read_only=True)

    class Meta:
        model = CropCycle
        fields = '__all__'
        extra_kwargs = {
            'crop_unit': {'required': False},
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if user is not None and user.is_authenticated:
            # Only let a user attach a crop to one of their own land portions.
            self.fields['field'].queryset = Field.objects.filter(farm__owner=user)

    def get_field_name(self, obj):
        unit = getattr(obj, 'crop_unit', None)
        if unit and unit.field:
            return unit.field.name
        return unit.unit_name if unit else None

    def validate(self, data):
        if not data.get('crop_unit') and not data.get('field'):
            raise serializers.ValidationError({'field': 'Please choose a land portion.'})
        for required in ('crop_type', 'planting_date'):
            if not data.get(required):
                raise serializers.ValidationError({required: 'This field is required.'})
        return data

    def _unit_for_field(self, field):
        unit, _ = CropUnit.objects.get_or_create(
            field=field,
            unit_type='field',
            defaults={'unit_name': field.name or 'Land portion'},
        )
        return unit

    def create(self, validated_data):
        field = validated_data.pop('field', None)
        if field is not None and not validated_data.get('crop_unit'):
            validated_data['crop_unit'] = self._unit_for_field(field)
        return super().create(validated_data)

    def update(self, instance, validated_data):
        field = validated_data.pop('field', None)
        if field is not None:
            validated_data['crop_unit'] = self._unit_for_field(field)
        return super().update(instance, validated_data)
