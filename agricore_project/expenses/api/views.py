from rest_framework import viewsets, permissions
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
