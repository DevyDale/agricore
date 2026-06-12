from django.contrib import admin
from .models import ExpenseCategory, Expense, ExpenseEvent, Payment

@admin.register(ExpenseCategory)
class ExpenseCategoryAdmin(admin.ModelAdmin):
    list_display = ("name", "description")
    search_fields = ("name",)

@admin.register(Expense)
class ExpenseAdmin(admin.ModelAdmin):
    list_display = ("name", "category", "total_cost", "date", "farm")
    list_filter = ("category", "farm", "date")
    search_fields = ("name", "vendor", "notes")

@admin.register(ExpenseEvent)
class ExpenseEventAdmin(admin.ModelAdmin):
    list_display = ("expense", "date", "amount", "is_recurring")
    list_filter = ("is_recurring", "date")

@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ("expense", "amount", "date", "status")
    list_filter = ("status", "date")
