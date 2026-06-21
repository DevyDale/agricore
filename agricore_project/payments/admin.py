from django.contrib import admin

from .models import PesapalPayment


@admin.register(PesapalPayment)
class PesapalPaymentAdmin(admin.ModelAdmin):
    list_display = ("merchant_ref", "order", "amount", "currency", "status", "created_at")
    list_filter = ("status", "currency")
    search_fields = ("merchant_ref", "order_tracking_id", "order__id")
    readonly_fields = ("created_at", "updated_at")
