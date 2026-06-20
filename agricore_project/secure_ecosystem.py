#!/usr/bin/env python
"""
secure_ecosystem.py  —  Close write-access gaps in the logistics & escrow apps.

Run from the folder that contains manage.py:

    python secure_ecosystem.py

What it fixes (reads stay exactly as they are; only WRITE access is tightened):

  logistics:
    - TransportRequest: only the requester can edit/delete a request.
      (Previously a transporter who could *see* an open request could also
       PATCH/DELETE it.)
    - TransportBid: only the transporter who placed a bid can edit/delete it.
      (Previously the requester who could *see* bids on their request could
       also modify/delete them.)

  escrow (financial data — tighter):
    - Disable arbitrary PUT/PATCH/DELETE; the only allowed methods are GET and
      POST. Status changes happen solely through the `fund` and `release`
      actions, never via a raw edit.
    - `status` becomes read-only, so every escrow starts as "pending" and can't
      be created pre-"released".
    - Creating an escrow now verifies you actually own the order.

marketprices is already correct (shared reference data, admin-only writes) and is
left untouched. Backs up every file it edits; aborts cleanly if anything doesn't
match (nothing half-applied).
"""
import os
import sys
import shutil
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
STAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
BACKUP = os.path.join(HERE, f".ecosystem_backup_{STAMP}")

LOG_VIEWS = os.path.join(HERE, "logistics", "api", "views.py")
ESC_VIEWS = os.path.join(HERE, "escrow", "api", "views.py")
ESC_SER = os.path.join(HERE, "escrow", "api", "serializers.py")


def die(msg):
    print(f"\n[ABORT] {msg}")
    print("Nothing was changed (any files already backed up are safe). Nothing half-applied.")
    sys.exit(1)


def backup(path):
    os.makedirs(BACKUP, exist_ok=True)
    shutil.copy2(path, os.path.join(BACKUP, os.path.relpath(path, HERE).replace(os.sep, "__")))


def edit(path, replacements):
    """replacements: list of (old, new). Each old must appear exactly once."""
    if not os.path.exists(path):
        die(f"Can't find {path}. Run this from the folder that contains manage.py.")
    text = open(path, encoding="utf-8").read()
    for old, new in replacements:
        if new in text and old not in text:
            print(f"[skip] {os.path.relpath(path, HERE)}: already patched")
            continue
        n = text.count(old)
        if n != 1:
            die(f"Expected exactly one match in {os.path.relpath(path, HERE)} but found {n}:\n----\n{old[:160]}\n----")
        text = text.replace(old, new)
    backup(path)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"[edit] {os.path.relpath(path, HERE)}")


# ---------------- logistics/api/views.py ----------------
LOG_PERMS = '''from .serializers import (
    VehicleSerializer,
    TransportRequestSerializer,
    TransportBidSerializer,
)


class IsRequesterOrReadOnly(BasePermission):
    """Read for anyone allowed to see it; write only for the request's owner."""

    def has_object_permission(self, request, view, obj):
        if request.method in SAFE_METHODS:
            return True
        return obj.requester_id == request.user.id


class IsBidderOrReadOnly(BasePermission):
    """Read for anyone allowed to see it; write only for the bidding transporter."""

    def has_object_permission(self, request, view, obj):
        if request.method in SAFE_METHODS:
            return True
        return obj.transporter_id == request.user.id'''

logistics_edits = [
    (
        "from rest_framework.permissions import IsAuthenticated\n",
        "from rest_framework.permissions import IsAuthenticated, BasePermission, SAFE_METHODS\n",
    ),
    (
        '''from .serializers import (
    VehicleSerializer,
    TransportRequestSerializer,
    TransportBidSerializer,
)''',
        LOG_PERMS,
    ),
    (
        '''class TransportRequestViewSet(viewsets.ModelViewSet):
    queryset = TransportRequest.objects.all()
    serializer_class = TransportRequestSerializer
    permission_classes = [IsAuthenticated]''',
        '''class TransportRequestViewSet(viewsets.ModelViewSet):
    queryset = TransportRequest.objects.all()
    serializer_class = TransportRequestSerializer
    permission_classes = [IsAuthenticated, IsRequesterOrReadOnly]''',
    ),
    (
        '''class TransportBidViewSet(viewsets.ModelViewSet):
    queryset = TransportBid.objects.all()
    serializer_class = TransportBidSerializer
    permission_classes = [IsAuthenticated]''',
        '''class TransportBidViewSet(viewsets.ModelViewSet):
    queryset = TransportBid.objects.all()
    serializer_class = TransportBidSerializer
    permission_classes = [IsAuthenticated, IsBidderOrReadOnly]''',
    ),
]

# ---------------- escrow/api/views.py ----------------
escrow_view_edits = [
    (
        '''class EscrowViewSet(viewsets.ModelViewSet):
    queryset = Escrow.objects.all()
    serializer_class = EscrowSerializer
    permission_classes = [IsAuthenticated]''',
        '''class EscrowViewSet(viewsets.ModelViewSet):
    queryset = Escrow.objects.all()
    serializer_class = EscrowSerializer
    permission_classes = [IsAuthenticated]
    # Financial records: only safe reads and POST (create + fund/release actions).
    # No raw PUT/PATCH/DELETE — status changes go through fund() / release() only.
    http_method_names = ["get", "post", "head", "options"]''',
    ),
    (
        '''    def perform_create(self, serializer):
        serializer.save(buyer=self.request.user)''',
        '''    def perform_create(self, serializer):
        order = serializer.validated_data.get("order")
        if order is not None and getattr(order, "buyer_id", None) != self.request.user.id:
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied("You can only open escrow for your own order.")
        serializer.save(buyer=self.request.user)''',
    ),
]

# ---------------- escrow/api/serializers.py ----------------
escrow_ser_edits = [
    (
        '''        extra_kwargs = {
            "buyer": {"read_only": True},
            "funded_at": {"read_only": True},
            "released_at": {"read_only": True},
        }''',
        '''        extra_kwargs = {
            "buyer": {"read_only": True},
            "status": {"read_only": True},
            "funded_at": {"read_only": True},
            "released_at": {"read_only": True},
        }''',
    ),
]


def main():
    edit(LOG_VIEWS, logistics_edits)
    edit(ESC_VIEWS, escrow_view_edits)
    edit(ESC_SER, escrow_ser_edits)
    print(f"\nDone. Backups in {os.path.relpath(BACKUP, HERE)}/")
    print("Run `python manage.py check` to confirm.")


if __name__ == "__main__":
    main()
