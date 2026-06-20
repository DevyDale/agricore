#!/usr/bin/env python3
"""
Agricore security patch: add ownership scoping (get_queryset / perform_create)
to viewsets that were exposing every user's data, and make owner/user fields
read-only in their serializers.

Run from the directory that contains manage.py:
    python security_fix.py

Safe to re-run: it errors loudly if a target block isn't found (e.g. already
patched) instead of corrupting a file. Backups are written to .security_backup/
"""
import os
import shutil
import sys
from datetime import datetime

BACKUP_DIR = ".security_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S")
edits = []   # (path, old, new, label)


def edit(path, old, new, label):
    edits.append((path, old, new, label))


# ---------------------------------------------------------------------------
# accounts/api/views.py
# ---------------------------------------------------------------------------
edit(
    "accounts/api/views.py",
    "from rest_framework.permissions import IsAuthenticated, AllowAny",
    "from rest_framework.permissions import IsAuthenticated, AllowAny, BasePermission, SAFE_METHODS",
    "accounts: import BasePermission/SAFE_METHODS",
)

edit(
    "accounts/api/views.py",
    """class CustomUserViewSet(viewsets.ModelViewSet):
    queryset = CustomUser.objects.all()
    serializer_class = CustomUserSerializer

    def get_permissions(self):
        if self.action == 'create':
            return [AllowAny()]  # Allow unauthenticated POST
        return [IsAuthenticated()]  # Require auth for other actions""",
    """class IsOwnerOrReadOnly(BasePermission):
    \"\"\"Read for any authenticated user; write only for the object's owner.\"\"\"
    def has_object_permission(self, request, view, obj):
        if request.method in SAFE_METHODS:
            return True
        return getattr(obj, 'user_id', None) == request.user.id


class CustomUserViewSet(viewsets.ModelViewSet):
    queryset = CustomUser.objects.all()
    serializer_class = CustomUserSerializer

    def get_permissions(self):
        if self.action == 'create':
            return [AllowAny()]  # Allow unauthenticated POST
        return [IsAuthenticated()]  # Require auth for other actions

    def get_queryset(self):
        user = self.request.user
        if not user.is_authenticated:
            return CustomUser.objects.none()
        if user.is_staff:
            return CustomUser.objects.all()
        return CustomUser.objects.filter(pk=user.pk)""",
    "accounts: CustomUserViewSet scoped to self/staff + IsOwnerOrReadOnly defined",
)

edit(
    "accounts/api/views.py",
    """class AttachmentViewSet(viewsets.ModelViewSet):
    queryset = Attachment.objects.all()
    serializer_class = AttachmentSerializer
    permission_classes = [IsAuthenticated]


class DigitalWalletViewSet(viewsets.ModelViewSet):
    queryset = DigitalWallet.objects.all()
    serializer_class = DigitalWalletSerializer
    permission_classes = [IsAuthenticated]


class SpecializedProfessionalViewSet(viewsets.ModelViewSet):
    queryset = SpecializedProfessional.objects.all()
    serializer_class = SpecializedProfessionalSerializer
    permission_classes = [IsAuthenticated]


class ReviewViewSet(viewsets.ModelViewSet):
    queryset = Review.objects.all()
    serializer_class = ReviewSerializer
    permission_classes = [IsAuthenticated]


class OnboardingProgressViewSet(viewsets.ModelViewSet):
    queryset = OnboardingProgress.objects.all()
    serializer_class = OnboardingProgressSerializer
    permission_classes = [IsAuthenticated]""",
    """class AttachmentViewSet(viewsets.ModelViewSet):
    queryset = Attachment.objects.all()
    serializer_class = AttachmentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Attachment.objects.filter(uploaded_by=self.request.user)

    def perform_create(self, serializer):
        serializer.save(uploaded_by=self.request.user)


class DigitalWalletViewSet(viewsets.ModelViewSet):
    queryset = DigitalWallet.objects.all()
    serializer_class = DigitalWalletSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return DigitalWallet.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class SpecializedProfessionalViewSet(viewsets.ModelViewSet):
    # Public professional directory: anyone authenticated can read,
    # but only the owner can edit/delete their own profile.
    queryset = SpecializedProfessional.objects.all()
    serializer_class = SpecializedProfessionalSerializer
    permission_classes = [IsAuthenticated, IsOwnerOrReadOnly]

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class ReviewViewSet(viewsets.ModelViewSet):
    # Reviews are publicly readable, but only the author can edit/delete.
    queryset = Review.objects.all()
    serializer_class = ReviewSerializer
    permission_classes = [IsAuthenticated, IsOwnerOrReadOnly]

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class OnboardingProgressViewSet(viewsets.ModelViewSet):
    queryset = OnboardingProgress.objects.all()
    serializer_class = OnboardingProgressSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return OnboardingProgress.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)""",
    "accounts: Attachment/Wallet/Professional/Review/Onboarding scoped",
)

# ---------------------------------------------------------------------------
# accounts/api/serializers.py  -> owner/user read-only
# ---------------------------------------------------------------------------
edit(
    "accounts/api/serializers.py",
    """class AttachmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Attachment
        fields = '__all__'""",
    """class AttachmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Attachment
        fields = '__all__'
        read_only_fields = ['uploaded_by']""",
    "accounts serializer: Attachment.uploaded_by read-only",
)
edit(
    "accounts/api/serializers.py",
    """class DigitalWalletSerializer(serializers.ModelSerializer):
    class Meta:
        model = DigitalWallet
        fields = '__all__'""",
    """class DigitalWalletSerializer(serializers.ModelSerializer):
    class Meta:
        model = DigitalWallet
        fields = '__all__'
        read_only_fields = ['user']""",
    "accounts serializer: DigitalWallet.user read-only",
)
edit(
    "accounts/api/serializers.py",
    """    class Meta:
        model = SpecializedProfessional
        fields = '__all__'""",
    """    class Meta:
        model = SpecializedProfessional
        fields = '__all__'
        read_only_fields = ['user']""",
    "accounts serializer: SpecializedProfessional.user read-only",
)
edit(
    "accounts/api/serializers.py",
    """class ReviewSerializer(serializers.ModelSerializer):
    class Meta:
        model = Review
        fields = '__all__'""",
    """class ReviewSerializer(serializers.ModelSerializer):
    class Meta:
        model = Review
        fields = '__all__'
        read_only_fields = ['user']""",
    "accounts serializer: Review.user read-only",
)
edit(
    "accounts/api/serializers.py",
    """class OnboardingProgressSerializer(serializers.ModelSerializer):
    class Meta:
        model = OnboardingProgress
        fields = '__all__'""",
    """class OnboardingProgressSerializer(serializers.ModelSerializer):
    class Meta:
        model = OnboardingProgress
        fields = '__all__'
        read_only_fields = ['user']""",
    "accounts serializer: OnboardingProgress.user read-only",
)

# ---------------------------------------------------------------------------
# marketplace/api/views.py  -> OrderItem / Payment / Shipping scoped by buyer
# ---------------------------------------------------------------------------
edit(
    "marketplace/api/views.py",
    """class OrderItemViewSet(viewsets.ModelViewSet):
    queryset = OrderItem.objects.all()
    serializer_class = OrderItemSerializer
    permission_classes = [IsAuthenticated]

class PaymentViewSet(viewsets.ModelViewSet):
    queryset = Payment.objects.all()
    serializer_class = PaymentSerializer
    permission_classes = [IsAuthenticated]

class ShippingViewSet(viewsets.ModelViewSet):
    queryset = Shipping.objects.all()
    serializer_class = ShippingSerializer
    permission_classes = [IsAuthenticated]""",
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
    "marketplace: OrderItem/Payment/Shipping scoped by order__buyer",
)

# ---------------------------------------------------------------------------
# crops/api/views.py  (file uses TABS)
# ---------------------------------------------------------------------------
edit(
    "crops/api/views.py",
    "class CropCycleViewSet(viewsets.ModelViewSet):\n"
    "\tqueryset = CropCycle.objects.all()\n"
    "\tserializer_class = CropCycleSerializer\n"
    "\tpermission_classes = [IsAuthenticated]",
    "class CropCycleViewSet(viewsets.ModelViewSet):\n"
    "\tqueryset = CropCycle.objects.all()\n"
    "\tserializer_class = CropCycleSerializer\n"
    "\tpermission_classes = [IsAuthenticated]\n"
    "\n"
    "\tdef get_queryset(self):\n"
    "\t\tfrom django.db.models import Q\n"
    "\t\tuser = self.request.user\n"
    "\t\t# Cycles on the user's farms, plus unassigned units (field is null)\n"
    "\t\treturn self.queryset.filter(\n"
    "\t\t\tQ(crop_unit__field__farm__owner=user) | Q(crop_unit__field__isnull=True)\n"
    "\t\t)",
    "crops: CropCycleViewSet scoped by crop_unit__field__farm__owner",
)

# ---------------------------------------------------------------------------
# livestock/api/views.py
# ---------------------------------------------------------------------------
edit(
    "livestock/api/views.py",
    """class AnimalReproductiveRecordViewSet(viewsets.ModelViewSet):
    queryset = AnimalReproductiveRecord.objects.all()
    serializer_class = AnimalReproductiveRecordSerializer
    permission_classes = [IsAuthenticated]""",
    """class AnimalReproductiveRecordViewSet(viewsets.ModelViewSet):
    queryset = AnimalReproductiveRecord.objects.all()
    serializer_class = AnimalReproductiveRecordSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(
            animal__livestock_unit__field__farm__owner=self.request.user
        )""",
    "livestock: AnimalReproductiveRecord scoped",
)
edit(
    "livestock/api/views.py",
    """class LivestockEmployeeAssignmentViewSet(viewsets.ModelViewSet):
    queryset = LivestockEmployeeAssignment.objects.all()
    serializer_class = LivestockEmployeeAssignmentSerializer
    permission_classes = [IsAuthenticated]""",
    """class LivestockEmployeeAssignmentViewSet(viewsets.ModelViewSet):
    queryset = LivestockEmployeeAssignment.objects.all()
    serializer_class = LivestockEmployeeAssignmentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(
            livestock_task__livestock_unit__field__farm__owner=self.request.user
        )""",
    "livestock: LivestockEmployeeAssignment scoped",
)

# ---------------------------------------------------------------------------
# communications/api/views.py
# ---------------------------------------------------------------------------
edit(
    "communications/api/views.py",
    """class ConversationParticipantViewSet(viewsets.ModelViewSet):
    queryset = ConversationParticipant.objects.all()
    serializer_class = ConversationParticipantSerializer
    permission_classes = [IsAuthenticated]""",
    """class ConversationParticipantViewSet(viewsets.ModelViewSet):
    queryset = ConversationParticipant.objects.all()
    serializer_class = ConversationParticipantSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(
            conversation__participants__user=self.request.user
        ).distinct()""",
    "communications: ConversationParticipant scoped",
)


# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------
def main():
    if not os.path.exists("manage.py"):
        sys.exit("ERROR: run this from the directory containing manage.py "
                 "(agricore_project/).")

    # Validate every edit first (no writes yet)
    problems = []
    for path, old, new, label in edits:
        if not os.path.exists(path):
            problems.append(f"  MISSING FILE: {path}  ({label})")
            continue
        with open(path, encoding="utf-8") as f:
            content = f.read()
        n = content.count(old)
        if n != 1:
            problems.append(f"  found {n} matches (expected 1) for: {label}  [{path}]")
    if problems:
        print("Aborting - the code didn't match what was expected:")
        print("\n".join(problems))
        print("\nNothing was changed.")
        sys.exit(1)

    os.makedirs(BACKUP_DIR, exist_ok=True)
    touched = {}
    for path, old, new, label in edits:
        with open(path, encoding="utf-8") as f:
            content = f.read()
        if path not in touched:
            dest = os.path.join(BACKUP_DIR, path)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(path, dest)
            touched[path] = True
        content = content.replace(old, new, 1)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"  [OK] {label}")

    print(f"\nPatched {len(touched)} files. Backups in {BACKUP_DIR}/")


if __name__ == "__main__":
    main()
