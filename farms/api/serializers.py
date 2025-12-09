from rest_framework import serializers
from ..models import Farm, Field, EnvironmentalData
from accounts.models import CustomUser
from datetime import datetime, date


class FarmSerializer(serializers.ModelSerializer):
    owner = serializers.PrimaryKeyRelatedField(queryset=CustomUser.objects.all())

    class Meta:
        model = Farm
        fields = [
            'id',
            'owner',
            'name',
            'type',
            'country',
            'state',
            'city',
            'address',
            'total_size',
            'size_unit',
            'last_visited',
            'additional_notes',
            'created_at',
            'updated_at',
        ]
        extra_kwargs = {
            'created_at': {'read_only': True},
            'updated_at': {'read_only': True},
            'last_visited': {'required': False, 'allow_null': True},
            'additional_notes': {'required': False, 'allow_blank': True},
        }

    def validate_type(self, value):
        valid_types = ['crops', 'livestock', 'mixed']
        if value not in valid_types:
            raise serializers.ValidationError(f"Type must be one of: {valid_types}")
        return value

    def validate_size_unit(self, value):
        valid_units = ['acres', 'hectares', 'square_meters']
        if value not in valid_units:
            raise serializers.ValidationError(f"Size unit must be one of: {valid_units}")
        return value


class FieldSerializer(serializers.ModelSerializer):
    farm = serializers.PrimaryKeyRelatedField(queryset=Farm.objects.all())

    class Meta:
        model = Field
        fields = [
            'id',
            'farm',
            'name',
            'purpose',
            'total_size',
            'size_unit',
            'soil_type',
            'additional_notes',
            'created_at',
            'updated_at',
        ]
        extra_kwargs = {
            'created_at': {'read_only': True},
            'updated_at': {'read_only': True},
            'purpose': {'required': False, 'allow_blank': True},
            'soil_type': {'required': False, 'allow_blank': True},
            'additional_notes': {'required': False, 'allow_blank': True},
        }

    def validate_purpose(self, value):
        valid_purposes = ['crop', 'livestock', 'other']
        if value and value not in valid_purposes:
            raise serializers.ValidationError(f"Purpose must be one of: {valid_purposes}")
        return value

    def validate_size_unit(self, value):
        valid_units = ['acres', 'hectares', 'square_meters']
        if value and value not in valid_units:
            raise serializers.ValidationError(f"Size unit must be one of: {valid_units}")
        return value


class EnvironmentalDataSerializer(serializers.ModelSerializer):
    farm = serializers.PrimaryKeyRelatedField(queryset=Farm.objects.all())

    class Meta:
        model = EnvironmentalData
        fields = [
            'id',
            'farm',
            'date',
            'temperature',
            'rainfall',
            'humidity',
            'soil_moisture',
            'pest_alerts',
            'additional_info',
            'created_at',
        ]
        extra_kwargs = {
            'created_at': {'read_only': True},
            'temperature': {'required': False, 'allow_null': True},
            'rainfall': {'required': False, 'allow_null': True},
            'humidity': {'required': False, 'allow_null': True},
            'soil_moisture': {'required': False, 'allow_null': True},
            'pest_alerts': {'required': False, 'allow_blank': True},
            'additional_info': {'required': False, 'allow_null': True},
        }

    def validate_temperature(self, value):
        if value is not None and (value < -50 or value > 60):
            raise serializers.ValidationError(
                "Temperature must be between -50 and 60 degrees Celsius."
            )
        return value

    def validate_rainfall(self, value):
        if value is not None and (value < 0 or value > 1000):
            raise serializers.ValidationError("Rainfall must be between 0 and 1000 mm.")
        return value

    def validate_humidity(self, value):
        if value is not None and (value < 0 or value > 100):
            raise serializers.ValidationError("Humidity must be between 0 and 100 percent.")
        return value

    def validate_soil_moisture(self, value):
        if value is not None and (value < 0 or value > 100):
            raise serializers.ValidationError("Soil moisture must be between 0 and 100 percent.")
        return value

    def validate_date(self, value):
        if value is not None and value > date.today():
            raise serializers.ValidationError("Date cannot be in the future.")
        return value

    def validate_additional_info(self, value):
        if value is not None and not isinstance(value, dict):
            raise serializers.ValidationError("Additional info must be a valid JSON object.")
        return value