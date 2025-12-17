from django.contrib import admin
from .models import Store, Product, Order, OrderItem, Payment, Shipping, Advertisement, StoreReview, ProductReview, PaymentCard

@admin.register(Store)
class StoreAdmin(admin.ModelAdmin):
    list_display = ['name', 'owner', 'is_verified', 'total_value', 'created_at']
    list_filter = ['is_verified', 'created_at']
    search_fields = ['name', 'owner__username', 'owner_email']

@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ['title', 'store', 'category', 'price', 'stock_quantity', 'created_at']
    list_filter = ['category', 'is_dropshippable', 'created_at']
    search_fields = ['title', 'description', 'store__name']

@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = ['id', 'buyer', 'store', 'total_amount', 'status', 'created_at']
    list_filter = ['status', 'created_at']
    search_fields = ['buyer__username', 'store__name']

@admin.register(OrderItem)
class OrderItemAdmin(admin.ModelAdmin):
    list_display = ['id', 'order', 'product', 'quantity', 'price_per_unit', 'subtotal']
    search_fields = ['order__id', 'product__title']

@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ['id', 'order', 'amount', 'method', 'provider', 'status', 'created_at']
    list_filter = ['status', 'method', 'provider', 'created_at']
    search_fields = ['order__id', 'provider_reference']

@admin.register(Shipping)
class ShippingAdmin(admin.ModelAdmin):
    list_display = ['id', 'order', 'provider', 'tracking_number', 'status', 'delivered_at']
    list_filter = ['status', 'provider']
    search_fields = ['tracking_number', 'order__id']

@admin.register(Advertisement)
class AdvertisementAdmin(admin.ModelAdmin):
    list_display = ['title', 'store', 'duration_days', 'price_paid', 'is_active', 'impressions', 'clicks', 'start_date', 'end_date']
    list_filter = ['is_active', 'duration_days', 'start_date']
    search_fields = ['title', 'description', 'store__name']
    readonly_fields = ['impressions', 'clicks', 'start_date', 'created_at', 'updated_at']

@admin.register(StoreReview)
class StoreReviewAdmin(admin.ModelAdmin):
    list_display = ['store', 'user', 'rating', 'created_at']
    list_filter = ['rating', 'created_at']
    search_fields = ['store__name', 'user__username', 'comment']

@admin.register(ProductReview)
class ProductReviewAdmin(admin.ModelAdmin):
    list_display = ['product', 'user', 'rating', 'created_at']
    list_filter = ['rating', 'created_at']
    search_fields = ['product__title', 'user__username', 'comment']

@admin.register(PaymentCard)
class PaymentCardAdmin(admin.ModelAdmin):
    list_display = ['user', 'cardholder_name', 'card_brand', 'card_number_last4', 'expiry_month', 'expiry_year', 'is_default']
    list_filter = ['card_brand', 'is_default']
    search_fields = ['user__username', 'cardholder_name', 'card_number_last4']
    readonly_fields = ['created_at', 'updated_at']
