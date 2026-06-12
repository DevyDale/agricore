
from rest_framework import serializers
from ..models import Farm, Field

# Serializer for Field (Land Portion)
class FieldSerializer(serializers.ModelSerializer):
    name = serializers.CharField(required=True, help_text="Name of the land portion (e.g., North Field, Plot A)")

    class Meta:
        model = Field
        fields = [
            'id', 'farm', 'name', 'purpose', 'total_size', 'size_unit',
            'soil_type', 'additional_notes', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']


class FarmSerializer(serializers.ModelSerializer):
    owner = serializers.PrimaryKeyRelatedField(read_only=True)

    # Enforce fields that are marked as required by the frontend/business logic
    name = serializers.CharField(required=True)
    type = serializers.CharField(required=True)
    country = serializers.CharField(required=True)
    city = serializers.CharField(required=True)
    state = serializers.CharField(required=True)
    total_size = serializers.FloatField(required=False, allow_null=True)
    address = serializers.CharField(allow_null=True, required=False)
    size_unit = serializers.CharField(allow_null=True, required=False)
    additional_notes = serializers.CharField(allow_null=True, required=False, allow_blank=True)
    created_at = serializers.DateTimeField(read_only=True)
    updated_at = serializers.DateTimeField(read_only=True)

    def validate_country(self, value):
        # Remove commas from the country name
        if value:
            return str(value).replace(',', '').strip()
        return value


    class Meta:
        model = Farm
        fields = [
            'id', 'owner', 'name', 'type', 'country', 'state', 'city',
            'address', 'total_size', 'size_unit', 'additional_notes',
            'created_at', 'updated_at'
        ]
        # Crucial to keep 'owner' in read_only_fields
        read_only_fields = ['owner', 'created_at', 'updated_at'] 

    def validate_type(self, value):
        # Your validation logic is sound. We don't need the 'if value is None' check 
        # if 'type' is set to required=True (since required=True means value won't be None)
        value = str(value).strip().lower()
        if value in ['crop', 'crops', 'c', 'farming']:
            return 'crops'
        if value in ['livestock', 'l', 'animals']:
            return 'livestock'
        if value in ['mixed', 'both', 'm']:
            return 'mixed'
        # Default fallback is fine, but should be hit rarely if frontend validates
        return 'crops'

    def validate_size_unit(self, value):
        if value is None:
            return None # Allow null if the field is optional
        return str(value)