from rest_framework import serializers
from livestock.models import LivestockUnit, Animal, AnimalReproductiveRecord, LivestockTask, LivestockEmployeeAssignment, LivestockExpense, AnimalMedicalRecord

class LivestockUnitSerializer(serializers.ModelSerializer):
    """
    Serializer for LivestockUnit, including produce fields:
    - produce_type
    - produce_frequency
    - produce_quantity
    - produce_unit
    """
    class Meta:
        model = LivestockUnit
        fields = '__all__'

    def validate(self, data):
        # Only require key features: unit_name, unit_type, and purpose
        errors = {}
        if not data.get('unit_name'):
            errors['unit_name'] = ['This field is required.']
        if not data.get('unit_type'):
            errors['unit_type'] = ['This field is required.']
        if not data.get('purpose'):
            errors['purpose'] = ['This field is required.']
        if errors:
            raise serializers.ValidationError(errors)
        return data

class AnimalSerializer(serializers.ModelSerializer):
    class Meta:
        model = Animal
        fields = '__all__'

class AnimalReproductiveRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = AnimalReproductiveRecord
        fields = '__all__'

class LivestockTaskSerializer(serializers.ModelSerializer):
    class Meta:
        model = LivestockTask
        fields = '__all__'

class LivestockEmployeeAssignmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = LivestockEmployeeAssignment
        fields = '__all__'

class LivestockExpenseSerializer(serializers.ModelSerializer):
    class Meta:
        model = LivestockExpense
        fields = '__all__'

class AnimalMedicalRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = AnimalMedicalRecord
        fields = '__all__'