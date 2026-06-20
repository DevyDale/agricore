#!/usr/bin/env python3
"""
Backend fix - build the expenses API (flat, owner-scoped).

Creates:
  expenses/api/__init__.py
  expenses/api/serializers.py
  expenses/api/views.py
  expenses/migrations/0002_seed_expense_categories.py   (seeds the 5 categories)

Edits:
  agricore_project/urls.py  (imports + 4 router registrations)

Endpoints (all require auth, all scoped to farms the user owns):
  GET             /api/expense-categories/      (read-only lookup)
  CRUD            /api/expenses/                ?farm=<id>
  CRUD            /api/expense-events/          ?expense=<id>
  CRUD            /api/expense-payments/        ?expense=<id>

Run from the directory containing manage.py:
    python build_expenses_api.py
Then:
    python manage.py migrate expenses
"""
import os
import sys
import shutil
from datetime import datetime

BACKUP = ".backend_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S")

SERIALIZERS = '''from rest_framework import serializers
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
'''

VIEWS = '''from rest_framework import viewsets, permissions
from rest_framework.exceptions import PermissionDenied
from expenses.models import ExpenseCategory, Expense, ExpenseEvent, Payment
from .serializers import (
    ExpenseCategorySerializer,
    ExpenseSerializer,
    ExpenseEventSerializer,
    ExpensePaymentSerializer,
)


class ExpenseCategoryViewSet(viewsets.ReadOnlyModelViewSet):
    """Global lookup table of expense categories (read-only)."""
    queryset = ExpenseCategory.objects.all()
    serializer_class = ExpenseCategorySerializer
    permission_classes = [permissions.IsAuthenticated]


class ExpenseViewSet(viewsets.ModelViewSet):
    serializer_class = ExpenseSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        qs = (Expense.objects
              .filter(farm__owner=self.request.user)
              .select_related("category", "farm")
              .prefetch_related("events", "payments"))
        farm_id = self.request.query_params.get("farm")
        if farm_id:
            try:
                qs = qs.filter(farm_id=int(farm_id))
            except (TypeError, ValueError):
                pass
        return qs

    def perform_create(self, serializer):
        farm = serializer.validated_data.get("farm")
        if farm is None or farm.owner_id != self.request.user.id:
            raise PermissionDenied("You do not own this farm.")
        serializer.save()

    def perform_update(self, serializer):
        farm = serializer.validated_data.get("farm")
        if farm is not None and farm.owner_id != self.request.user.id:
            raise PermissionDenied("You do not own this farm.")
        serializer.save()


class _ExpenseChildViewSet(viewsets.ModelViewSet):
    """Shared scoping for objects that hang off an Expense (events, payments)."""
    permission_classes = [permissions.IsAuthenticated]
    filter_param = "expense"

    def get_queryset(self):
        qs = self.model.objects.filter(expense__farm__owner=self.request.user)
        expense_id = self.request.query_params.get(self.filter_param)
        if expense_id:
            try:
                qs = qs.filter(expense_id=int(expense_id))
            except (TypeError, ValueError):
                pass
        return qs

    def _check(self, serializer):
        expense = serializer.validated_data.get("expense")
        if expense is not None and expense.farm.owner_id != self.request.user.id:
            raise PermissionDenied("You do not own this expense's farm.")

    def perform_create(self, serializer):
        self._check(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._check(serializer)
        serializer.save()


class ExpenseEventViewSet(_ExpenseChildViewSet):
    model = ExpenseEvent
    serializer_class = ExpenseEventSerializer


class ExpensePaymentViewSet(_ExpenseChildViewSet):
    model = Payment
    serializer_class = ExpensePaymentSerializer
'''

SEED_MIGRATION = '''from django.db import migrations

CATEGORIES = [
    ("input", "Seeds, fertilizer, feed, agro-chemicals"),
    ("labor", "Wages and labor costs"),
    ("equipment", "Equipment purchase and maintenance"),
    ("utilities", "Water, power, fuel"),
    ("overhead", "Miscellaneous and overhead"),
]


def seed(apps, schema_editor):
    ExpenseCategory = apps.get_model("expenses", "ExpenseCategory")
    for name, desc in CATEGORIES:
        ExpenseCategory.objects.get_or_create(name=name, defaults={"description": desc})


def unseed(apps, schema_editor):
    ExpenseCategory = apps.get_model("expenses", "ExpenseCategory")
    ExpenseCategory.objects.filter(name__in=[c[0] for c in CATEGORIES]).delete()


class Migration(migrations.Migration):
    dependencies = [("expenses", "0001_initial")]
    operations = [migrations.RunPython(seed, unseed)]
'''

URLS_IMPORT_ANCHOR = "from escrow.api.views import EscrowViewSet"
URLS_IMPORT_ADD = """from escrow.api.views import EscrowViewSet
from expenses.api.views import (
    ExpenseCategoryViewSet,
    ExpenseViewSet,
    ExpenseEventViewSet,
    ExpensePaymentViewSet,
)"""

URLS_REG_ANCHOR = "router.register(r'escrows', EscrowViewSet, basename='escrow')"
URLS_REG_ADD = """router.register(r'escrows', EscrowViewSet, basename='escrow')

# Expenses
router.register(r'expense-categories', ExpenseCategoryViewSet, basename='expensecategory')
router.register(r'expenses', ExpenseViewSet, basename='expense')
router.register(r'expense-events', ExpenseEventViewSet, basename='expenseevent')
router.register(r'expense-payments', ExpensePaymentViewSet, basename='expensepayment')"""


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  [new] {path}")


def main():
    if not os.path.exists("manage.py"):
        sys.exit("ERROR: run from the directory containing manage.py (agricore_project/).")

    urls = "agricore_project/urls.py"
    with open(urls, encoding="utf-8") as f:
        urls_src = f.read()

    if "expenses.api.views" in urls_src:
        sys.exit("expenses already wired into urls.py - aborting (no changes).")
    if urls_src.count(URLS_IMPORT_ANCHOR) != 1 or urls_src.count(URLS_REG_ANCHOR) != 1:
        sys.exit("ERROR: urls.py anchors not found exactly once; aborting (no changes).")

    os.makedirs(BACKUP, exist_ok=True)
    shutil.copy2(urls, os.path.join(BACKUP, "urls.py"))

    write("expenses/api/__init__.py", "")
    write("expenses/api/serializers.py", SERIALIZERS)
    write("expenses/api/views.py", VIEWS)
    write("expenses/migrations/0002_seed_expense_categories.py", SEED_MIGRATION)

    urls_src = urls_src.replace(URLS_IMPORT_ANCHOR, URLS_IMPORT_ADD, 1)
    urls_src = urls_src.replace(URLS_REG_ANCHOR, URLS_REG_ADD, 1)
    with open(urls, "w", encoding="utf-8") as f:
        f.write(urls_src)
    print(f"  [edit] {urls} (imports + 4 routes)")

    print(f"\nDone. Backup of urls.py in {BACKUP}/")
    print("Next: python manage.py migrate expenses")


if __name__ == "__main__":
    main()
