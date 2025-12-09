from rest_framework import serializers
from workforce.models import Employee, Machinery, Equipment, EmployeePerformance, FiredEmployee

class EmployeeSerializer(serializers.ModelSerializer):
    class Meta:
        model = Employee
        fields = '__all__'

class MachinerySerializer(serializers.ModelSerializer):
    class Meta:
        model = Machinery
        fields = '__all__'

class EquipmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Equipment
        fields = '__all__'

class EmployeePerformanceSerializer(serializers.ModelSerializer):
    class Meta:
        model = EmployeePerformance
        fields = '__all__'

class FiredEmployeeSerializer(serializers.ModelSerializer):
    class Meta:
        model = FiredEmployee
        fields = '__all__'