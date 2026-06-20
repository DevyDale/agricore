#!/usr/bin/env python3
"""
Backend hardening:
  #5  Registration ran create_user() without Django's password validators, so
      weak passwords slipped through. Add validate_password() to the user
      serializer (enforces AUTH_PASSWORD_VALIDATORS on signup).
  #6  OrderItem/Payment/Shipping reads were already locked to the buyer, but
      *create* let a user attach rows to someone else's order. Reject creates
      whose order isn't owned by the requester.

Run from the directory containing manage.py:
    python backend_hardening.py
"""
import os
import sys
import shutil
from datetime import datetime

BACKUP = ".backend_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S")
edits = []


def edit(path, old, new, label):
    edits.append((path, old, new, label))


# ---- #5 password validation on registration -------------------------------
edit(
    "accounts/api/serializers.py",
    """        }

    def create(self, validated_data):
        password = validated_data.pop('password')""",
    """        }

    def validate_password(self, value):
        from django.contrib.auth.password_validation import validate_password
        validate_password(value)
        return value

    def create(self, validated_data):
        password = validated_data.pop('password')""",
    "accounts: enforce password validators on registration",
)

# ---- #6 order-ownership on create -----------------------------------------
edit(
    "marketplace/api/views.py",
    """from rest_framework.decorators import action
from rest_framework.response import Response
from marketplace.models import""",
    """from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.exceptions import PermissionDenied
from marketplace.models import""",
    "marketplace: import PermissionDenied",
)

edit(
    "marketplace/api/views.py",
    """class OrderItemViewSet(viewsets.ModelViewSet):
    queryset = OrderItem.objects.all()
    serializer_class = OrderItemSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(order__buyer=self.request.user)

class PaymentViewSet(viewsets.ModelViewSet):
    queryset = Payment.objects.all()
    serializer_class = PaymentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(order__buyer=self.request.user)

class ShippingViewSet(viewsets.ModelViewSet):
    queryset = Shipping.objects.all()
    serializer_class = ShippingSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(order__buyer=self.request.user)""",
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
        serializer.save()

class PaymentViewSet(viewsets.ModelViewSet):
    queryset = Payment.objects.all()
    serializer_class = PaymentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(order__buyer=self.request.user)

    def perform_create(self, serializer):
        order = serializer.validated_data.get('order')
        if order is None or order.buyer_id != self.request.user.id:
            raise PermissionDenied("You can only add payments to your own orders.")
        serializer.save()

class ShippingViewSet(viewsets.ModelViewSet):
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
    "marketplace: OrderItem/Payment/Shipping ownership check on create",
)


def main():
    if not os.path.exists("manage.py"):
        sys.exit("ERROR: run from the directory containing manage.py (agricore_project/).")

    problems = []
    for path, old, new, label in edits:
        if not os.path.exists(path):
            problems.append(f"  MISSING: {path} ({label})")
            continue
        with open(path, encoding="utf-8") as f:
            c = f.read()
        if c.count(old) != 1:
            problems.append(f"  {c.count(old)} matches (want 1): {label} [{path}]")
    if problems:
        print("Aborting - code didn't match expected:")
        print("\n".join(problems))
        sys.exit(1)

    os.makedirs(BACKUP, exist_ok=True)
    touched = {}
    for path, old, new, label in edits:
        with open(path, encoding="utf-8") as f:
            c = f.read()
        if path not in touched:
            dest = os.path.join(BACKUP, path)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(path, dest)
            touched[path] = True
        with open(path, "w", encoding="utf-8") as f:
            f.write(c.replace(old, new, 1))
        print(f"  [OK] {label}")

    print(f"\nPatched {len(touched)} files. Backups in {BACKUP}/")


if __name__ == "__main__":
    main()
