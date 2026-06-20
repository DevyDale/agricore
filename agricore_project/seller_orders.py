#!/usr/bin/env python3
"""
Seller-side order visibility.

Orders were scoped to the buyer only, so store owners couldn't see orders placed
to their stores (no way to fulfill them). This makes orders / order-items /
payments / shipping visible to BOTH the buyer and the store owner, and lets the
seller (as well as the buyer) create/update shipping rows. Item and payment
creation stay buyer-only.

Run from the directory containing manage.py:
    python seller_orders.py
"""
import os
import sys
import shutil
from datetime import datetime

BACKUP = ".backend_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S")
PATH = "marketplace/api/views.py"
edits = []


def edit(old, new, label):
    edits.append((old, new, label))


edit(
    """    def get_queryset(self):
        return self.queryset.filter(buyer=self.request.user)  # Or store__owner for sellers""",
    """    def get_queryset(self):
        user = self.request.user
        # Buyers see orders they placed; sellers see orders to stores they own.
        return self.queryset.filter(Q(buyer=user) | Q(store__owner=user)).distinct()""",
    "OrderViewSet: buyer or store owner",
)

edit(
    """class OrderItemViewSet(viewsets.ModelViewSet):
    queryset = OrderItem.objects.all()
    serializer_class = OrderItemSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(order__buyer=self.request.user)

    def perform_create(self, serializer):
        order = serializer.validated_data.get('order')
        if order is None or order.buyer_id != self.request.user.id:
            raise PermissionDenied("You can only add items to your own orders.")
        serializer.save()""",
    """class OrderItemViewSet(viewsets.ModelViewSet):
    queryset = OrderItem.objects.all()
    serializer_class = OrderItemSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        return self.queryset.filter(
            Q(order__buyer=user) | Q(order__store__owner=user)
        ).distinct()

    def perform_create(self, serializer):
        order = serializer.validated_data.get('order')
        if order is None or order.buyer_id != self.request.user.id:
            raise PermissionDenied("You can only add items to your own orders.")
        serializer.save()""",
    "OrderItemViewSet: seller can view, buyer-only create",
)

edit(
    """class PaymentViewSet(viewsets.ModelViewSet):
    queryset = Payment.objects.all()
    serializer_class = PaymentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(order__buyer=self.request.user)

    def perform_create(self, serializer):
        order = serializer.validated_data.get('order')
        if order is None or order.buyer_id != self.request.user.id:
            raise PermissionDenied("You can only add payments to your own orders.")
        serializer.save()""",
    """class PaymentViewSet(viewsets.ModelViewSet):
    queryset = Payment.objects.all()
    serializer_class = PaymentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        return self.queryset.filter(
            Q(order__buyer=user) | Q(order__store__owner=user)
        ).distinct()

    def perform_create(self, serializer):
        order = serializer.validated_data.get('order')
        if order is None or order.buyer_id != self.request.user.id:
            raise PermissionDenied("You can only add payments to your own orders.")
        serializer.save()""",
    "PaymentViewSet: seller can view, buyer-only create",
)

edit(
    """class ShippingViewSet(viewsets.ModelViewSet):
    queryset = Shipping.objects.all()
    serializer_class = ShippingSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(order__buyer=self.request.user)

    def perform_create(self, serializer):
        order = serializer.validated_data.get('order')
        if order is None or order.buyer_id != self.request.user.id:
            raise PermissionDenied("You can only add shipping to your own orders.")
        serializer.save()""",
    """class ShippingViewSet(viewsets.ModelViewSet):
    queryset = Shipping.objects.all()
    serializer_class = ShippingSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        return self.queryset.filter(
            Q(order__buyer=user) | Q(order__store__owner=user)
        ).distinct()

    def perform_create(self, serializer):
        # Sellers fulfill shipping; buyers may also create it for their own orders.
        order = serializer.validated_data.get('order')
        if order is None or (
            order.buyer_id != self.request.user.id
            and order.store.owner_id != self.request.user.id
        ):
            raise PermissionDenied("You can only manage shipping for your own orders.")
        serializer.save()""",
    "ShippingViewSet: seller can view + fulfill shipping",
)


def main():
    if not os.path.exists("manage.py"):
        sys.exit("ERROR: run from the directory containing manage.py (agricore_project/).")
    if not os.path.exists(PATH):
        sys.exit(f"ERROR: missing {PATH}")

    with open(PATH, encoding="utf-8") as f:
        src = f.read()

    problems = [lbl for old, new, lbl in edits if src.count(old) != 1]
    if problems:
        print("Aborting - code didn't match expected for:")
        for p in problems:
            print("  -", p)
        sys.exit(1)

    os.makedirs(BACKUP, exist_ok=True)
    dest = os.path.join(BACKUP, PATH)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.copy2(PATH, dest)

    for old, new, lbl in edits:
        src = src.replace(old, new, 1)
        print(f"  [OK] {lbl}")
    with open(PATH, "w", encoding="utf-8") as f:
        f.write(src)

    print(f"\nPatched {PATH}. Backup in {BACKUP}/")


if __name__ == "__main__":
    main()
