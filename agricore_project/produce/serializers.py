# produce/serializers.py
from rest_framework import serializers
from .models import ProduceCollection
from marketplace.models import Product

class ProduceCollectionSerializer(serializers.ModelSerializer):
    # The API route is nested under farms and the view sets `farm` via `perform_create`.
    # Mark `farm` as read-only so it is not required in the POST body (i.e., the nested URL determines the farm).
    farm = serializers.PrimaryKeyRelatedField(read_only=True)
    # Added fields for display and farm name
    source_display = serializers.CharField(source='get_source_display', read_only=True)
    farm_name = serializers.CharField(source='farm.name', read_only=True)
    
    # Made created_at and updated_at explicitly read-only for clarity
    created_at = serializers.DateTimeField(read_only=True)
    updated_at = serializers.DateTimeField(read_only=True)
    linked_products = serializers.SerializerMethodField(read_only=True)

    class Meta:
        model = ProduceCollection
        fields = [
            'id', 'farm', 'farm_name',
            'source', 'source_display',
            'product_name', 'quantity', 'unit',
            'collection_date', 'quality_grade',
            'notes', 'created_at', 'updated_at',
            'linked_products'
        ]
        # Redundant if declared above, but keeps the original spirit
        read_only_fields = ['created_at', 'updated_at'] 

    def validate(self, data):
        # Validate that quantity exists and is positive
        quantity = data.get('quantity')
        if quantity is not None and quantity <= 0:
            raise serializers.ValidationError({"quantity": "Must be greater than zero."})
        return data

    def get_linked_products(self, obj):
        # Return a simple representation of linked products if any
        prods = Product.objects.filter(source_produce=obj)
        if not prods.exists():
            return []
        return [
            {
                'id': p.id,
                'title': p.title,
                'price': str(p.price),
                'stock_quantity': str(p.stock_quantity),
                'unit': p.unit,
                'store': p.store.id,
                'store_name': p.store.name
            }
            for p in prods
        ]