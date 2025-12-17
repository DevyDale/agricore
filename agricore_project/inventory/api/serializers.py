from rest_framework import serializers
from inventory.models import Inventory, ProductionRecord

class InventorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Inventory
        fields = '__all__'

class ProductionRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProductionRecord
        fields = '__all__'