from django.db import models
from accounts.models import CustomUser
from farms.models import Farm

class Store(models.Model):
    owner = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name='stores') # <--- ADD THIS LINE
    farm = models.ForeignKey(Farm, on_delete=models.SET_NULL, null=True, blank=True)
    name = models.CharField(max_length=255)
    description = models.TextField(blank=True, default='')
    owner_name = models.CharField(max_length=255, default='Unknown')
    owner_phone = models.CharField(max_length=255, blank=True, default='')
    owner_email = models.EmailField(blank=True, default='')
    countries_of_operation = models.CharField(max_length=255, blank=True, default='')
    total_value = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    is_verified = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class Product(models.Model):
    store = models.ForeignKey(Store, on_delete=models.CASCADE)
    title = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    category = models.CharField(max_length=50)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    stock_quantity = models.DecimalField(max_digits=10, decimal_places=2)
    unit = models.CharField(max_length=20)
    is_dropshippable = models.BooleanField(default=False)
    total_value = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    expiration_date = models.DateField(blank=True, null=True)
    # Link back to the ProduceCollection source if this product originated from a farm's produce
    source_produce = models.ForeignKey('produce.ProduceCollection', on_delete=models.SET_NULL, null=True, blank=True, related_name='linked_products')
    # Image handling: supports both file upload and URL
    image = models.ImageField(upload_to='products/', blank=True, null=True)
    image_url = models.URLField(blank=True, null=True, help_text='Alternative to uploading: provide image URL')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class Order(models.Model):
    buyer = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    store = models.ForeignKey(Store, on_delete=models.CASCADE)
    total_amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=50)
    shipping_address = models.TextField(blank=True)
    transport_mode = models.CharField(max_length=50, blank=True)
    # 🌟 NEW FIX: Added related_name here to prevent reverse accessor clashes on the Payment model.
    payment = models.ForeignKey('Payment', related_name='linked_order', on_delete=models.SET_NULL, null=True, blank=True) 
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class OrderItem(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE)
    product = models.ForeignKey(Product, on_delete=models.CASCADE)
    quantity = models.DecimalField(max_digits=10, decimal_places=2)
    price_per_unit = models.DecimalField(max_digits=10, decimal_places=2)
    subtotal = models.DecimalField(max_digits=10, decimal_places=2)

class Payment(models.Model):
    # PREVIOUS FIX: related_name here prevents reverse accessor clashes on the Order model.
    order = models.ForeignKey(Order, related_name='payment_details', on_delete=models.CASCADE) 
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    method = models.CharField(max_length=50)
    provider = models.CharField(max_length=50)
    provider_reference = models.CharField(max_length=255, blank=True)
    status = models.CharField(max_length=50)
    created_at = models.DateTimeField(auto_now_add=True)

class Shipping(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE)
    provider = models.CharField(max_length=50)
    tracking_number = models.CharField(max_length=255, blank=True)
    status = models.CharField(max_length=50)
    estimated_delivery_date = models.DateField(blank=True, null=True)
    shipped_at = models.DateTimeField(blank=True, null=True)
    delivered_at = models.DateTimeField(blank=True, null=True)

class Advertisement(models.Model):
    store = models.ForeignKey(Store, on_delete=models.CASCADE, related_name='advertisements')
    title = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    image = models.ImageField(upload_to='advertisements/', blank=True, null=True)
    background_color = models.CharField(max_length=7, default='#10b981')
    text_color = models.CharField(max_length=7, default='#ffffff')
    cta_text = models.CharField(max_length=100, default='Shop Now')
    link_url = models.URLField(blank=True)
    font_family = models.CharField(max_length=100, default='Inter, sans-serif')
    title_font_size = models.IntegerField(default=30)
    description_font_size = models.IntegerField(default=18)
    image_fit = models.CharField(max_length=20, default='cover')
    image_position = models.CharField(max_length=20, default='center')
    image_brightness = models.IntegerField(default=100)
    audio = models.FileField(upload_to='advertisements/audio/', blank=True, null=True)
    duration_days = models.IntegerField(default=1)
    price_paid = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    is_active = models.BooleanField(default=True)
    start_date = models.DateTimeField(auto_now_add=True)
    end_date = models.DateTimeField(null=True, blank=True)
    impressions = models.IntegerField(default=0)
    clicks = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class StoreReview(models.Model):
    store = models.ForeignKey(Store, on_delete=models.CASCADE, related_name='store_reviews')
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    rating = models.IntegerField(default=5)
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ['store', 'user']

class ProductReview(models.Model):
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name='product_reviews')
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    rating = models.IntegerField(default=5)
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ['product', 'user']

class PaymentCard(models.Model):
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name='payment_cards')
    cardholder_name = models.CharField(max_length=255)
    card_number_last4 = models.CharField(max_length=4)
    card_brand = models.CharField(max_length=50, blank=True)
    expiry_month = models.IntegerField()
    expiry_year = models.IntegerField()
    is_default = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
