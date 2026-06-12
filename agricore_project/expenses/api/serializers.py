from rest_framework import serializers
from expenses.models import ExpenseCategory, Expense, ExpenseEvent, Payment


class ExpenseCategorySerializer(serializers.ModelSerializer):
    display_name = serializers.CharField(source="get_name_display", read_only=True)

    class Meta:
        model = ExpenseCategory
        fields = ["id", "name", "display_name", "description"]


class ExpenseEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = ExpenseEvent
        fields = "__all__"


class ExpensePaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Payment
        fields = "__all__"


class ExpenseSerializer(serializers.ModelSerializer):
    category_name = serializers.CharField(source="category.get_name_display", read_only=True)
    farm_name = serializers.CharField(source="farm.name", read_only=True)
    events = ExpenseEventSerializer(many=True, read_only=True)
    payments = ExpensePaymentSerializer(many=True, read_only=True)

    class Meta:
        model = Expense
        fields = [
            "id", "category", "category_name", "name", "quantity", "unit",
            "unit_cost", "total_cost", "date", "notes", "vendor", "payment_method",
            "content_type", "object_id", "farm", "farm_name", "created_by",
            "events", "payments", "created_at", "updated_at",
        ]
        # total_cost is computed in Expense.save(); timestamps are automatic.
        read_only_fields = ["total_cost", "created_at", "updated_at"]
