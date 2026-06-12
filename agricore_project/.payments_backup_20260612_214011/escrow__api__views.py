from django.db.models import Q
from django.utils import timezone
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from escrow.models import Escrow
from .serializers import EscrowSerializer


class EscrowViewSet(viewsets.ModelViewSet):
    queryset = Escrow.objects.all()
    serializer_class = EscrowSerializer
    permission_classes = [IsAuthenticated]
    # Financial records: only safe reads and POST (create + fund/release actions).
    # No raw PUT/PATCH/DELETE — status changes go through fund() / release() only.
    http_method_names = ["get", "post", "head", "options"]

    def get_queryset(self):
        # Visible to the buyer and to the seller (store owner) on the order.
        user = self.request.user
        return Escrow.objects.filter(
            Q(buyer=user) | Q(order__store__owner=user)
        ).distinct()

    def perform_create(self, serializer):
        order = serializer.validated_data.get("order")
        if order is not None and getattr(order, "buyer_id", None) != self.request.user.id:
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied("You can only open escrow for your own order.")
        serializer.save(buyer=self.request.user)

    @action(detail=True, methods=["post"])
    def fund(self, request, pk=None):
        """Mark funds as held (in a real system this follows a payment webhook)."""
        escrow = self.get_object()
        if escrow.buyer != request.user:
            return Response(
                {"detail": "Only the buyer can fund this escrow."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if escrow.status != "pending":
            return Response(
                {"detail": f"Cannot fund from status: {escrow.status}."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        escrow.status = "held"
        escrow.funded_at = timezone.now()
        escrow.save()
        return Response(self.get_serializer(escrow).data)

    @action(detail=True, methods=["post"])
    def release(self, request, pk=None):
        """Buyer confirms delivery and releases funds to the seller."""
        escrow = self.get_object()
        if escrow.buyer != request.user:
            return Response(
                {"detail": "Only the buyer can release funds."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if escrow.status != "held":
            return Response(
                {"detail": f"Cannot release from status: {escrow.status}."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        escrow.status = "released"
        escrow.released_at = timezone.now()
        escrow.save()
        return Response(self.get_serializer(escrow).data)
