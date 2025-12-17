from rest_framework import serializers
from livestock.models import LivestockUnit, Animal, AnimalReproductiveRecord, LivestockTask, LivestockEmployeeAssignment, LivestockExpense, AnimalMedicalRecord

class LivestockUnitSerializer(serializers.ModelSerializer):
    class Meta:
        model = LivestockUnit
        fields = '__all__'

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