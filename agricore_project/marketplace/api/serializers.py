from rest_framework import serializers
from marketplace.models import Store, Product, Order, OrderItem, Payment, Shipping, Advertisement, StoreReview, ProductReview, PaymentCard
from produce.models import ProduceCollection
class StoreSerializer(serializers.ModelSerializer):
    # Field to handle the array input from the frontend and convert it to a string for the model
    # It handles both writing (array to string) and reading (string from model)
    countries_of_operation = serializers.ListField(
        child=serializers.CharField(max_length=200),
        allow_empty=True,
        required=False,
    )

    class Meta:
        model = Store
        fields = [
            'id',
            'owner', # <--- ADD THIS LINE
            'farm',  # <--- ADD THIS LINE - needed for linking stores to farms
            'name',
            'description',
            'owner_name',
            'owner_phone',
            'owner_email',
            'countries_of_operation',
            'total_value', # Include fields you want to return
            'is_verified', # Renamed from 'verified' in frontend, check below
        ]
        read_only_fields = ['owner', 'total_value'] # owner is set by the viewset

    def to_representation(self, instance):
        # Convert the countries string from the model back to an array for the frontend
        representation = super().to_representation(instance)
        # Check if the field is a string before splitting
        countries_str = representation.get('countries_of_operation')
        if isinstance(countries_str, str):
            # Assumes countries are stored as comma-separated string
            representation['countries_of_operation'] = [s.strip() for s in countries_str.split(',') if s.strip()]
        return representation

    def to_internal_value(self, data):
        # Convert the countries array from the frontend into a comma-separated string for the model
        internal_value = super().to_internal_value(data)
        countries_list = data.get('countries_of_operation')
        if isinstance(countries_list, list):
            internal_value['countries_of_operation'] = ', '.join(countries_list)
        return internal_value

class ProductSerializer(serializers.ModelSerializer):
    source_produce = serializers.PrimaryKeyRelatedField(queryset=ProduceCollection.objects.all(), required=False, allow_null=True)
    source_produce_info = serializers.SerializerMethodField(read_only=True)
    store_name = serializers.CharField(source='store.name', read_only=True)
    store_verified = serializers.BooleanField(source='store.is_verified', read_only=True)
    store_owner_name = serializers.CharField(source='store.owner_name', read_only=True)
    store_owner_phone = serializers.CharField(source='store.owner_phone', read_only=True)
    store_owner_email = serializers.EmailField(source='store.owner_email', read_only=True)
    average_rating = serializers.FloatField(read_only=True)
    reviews_count = serializers.IntegerField(read_only=True)
    image_display = serializers.SerializerMethodField(read_only=True)

    class Meta:
        model = Product
        fields = '__all__'

    def get_image_display(self, obj):
        """Return absolute URL for image (from file or URL field)"""
        request = self.context.get('request')
        if obj.image:
            if request:
                return request.build_absolute_uri(obj.image.url)
            return obj.image.url
        elif obj.image_url:
            return obj.image_url
        return None

    def get_source_produce_info(self, obj):
        if not obj.source_produce:
            return None
        return {
            'id': obj.source_produce.id,
            'product_name': obj.source_produce.product_name,
            'farm_id': obj.source_produce.farm_id,
            'farm_name': getattr(obj.source_produce.farm, 'name', None),
        }

class OrderSerializer(serializers.ModelSerializer):
    class Meta:
        model = Order
        fields = '__all__'

class OrderItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderItem
        fields = '__all__'

class PaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Payment
        fields = '__all__'

class ShippingSerializer(serializers.ModelSerializer):
    class Meta:
        model = Shipping
        fields = '__all__'

class AdvertisementSerializer(serializers.ModelSerializer):
    class Meta:
        model = Advertisement
        fields = '__all__'
        read_only_fields = ['impressions', 'clicks', 'start_date', 'created_at', 'updated_at']

class StoreReviewSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source='user.username', read_only=True)
    
    class Meta:
        model = StoreReview
        fields = '__all__'
        read_only_fields = ['user', 'created_at', 'updated_at']

class ProductReviewSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source='user.username', read_only=True)
    
    class Meta:
        model = ProductReview
        fields = '__all__'
        read_only_fields = ['user', 'created_at', 'updated_at']

class PaymentCardSerializer(serializers.ModelSerializer):
    card_number = serializers.CharField(write_only=True, required=False)
    cvv = serializers.CharField(write_only=True, required=False)
    
    class Meta:
        model = PaymentCard
        fields = ['id', 'cardholder_name', 'card_number', 'card_number_last4', 'card_brand', 
                  'expiry_month', 'expiry_year', 'is_default', 'cvv', 'created_at', 'updated_at']
        read_only_fields = ['user', 'card_number_last4', 'card_brand', 'created_at', 'updated_at']
    
    def create(self, validated_data):
        card_number = validated_data.pop('card_number', None)
        validated_data.pop('cvv', None)  # Remove CVV, never store it
        
        if card_number:
            # Extract last 4 digits
            validated_data['card_number_last4'] = card_number[-4:]
            # Detect card brand (simple logic)
            if card_number.startswith('4'):
                validated_data['card_brand'] = 'Visa'
            elif card_number.startswith(('51', '52', '53', '54', '55')):
                validated_data['card_brand'] = 'Mastercard'
            elif card_number.startswith(('34', '37')):
                validated_data['card_brand'] = 'Amex'
            else:
                validated_data['card_brand'] = 'Unknown'
        
        return super().create(validated_data)