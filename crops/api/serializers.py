from rest_framework import serializers
from crops.models import Crop, CropTask, CropEmployeeAssignment, CropExpense

class CropSerializer(serializers.ModelSerializer):
    class Meta:
        model = Crop
        fields = '__all__'

class CropTaskSerializer(serializers.ModelSerializer):
    class Meta:
        model = CropTask
        fields = '__all__'

class CropEmployeeAssignmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = CropEmployeeAssignment
        fields = '__all__'

class CropExpenseSerializer(serializers.ModelSerializer):
    class Meta:
        model = CropExpense
        fields = '__all__'