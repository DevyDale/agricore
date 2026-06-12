from django.db.models import Q
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from logistics.models import Vehicle, TransportRequest, TransportBid
from .serializers import (
    VehicleSerializer,
    TransportRequestSerializer,
    TransportBidSerializer,
)


class VehicleViewSet(viewsets.ModelViewSet):
    queryset = Vehicle.objects.all()
    serializer_class = VehicleSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Vehicle.objects.filter(transporter=self.request.user)

    def perform_create(self, serializer):
        serializer.save(transporter=self.request.user)


class TransportRequestViewSet(viewsets.ModelViewSet):
    queryset = TransportRequest.objects.all()
    serializer_class = TransportRequestSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        # Requesters see their own requests; transporters see open requests
        # they can bid on.
        user = self.request.user
        return TransportRequest.objects.filter(
            Q(requester=user) | Q(status="open")
        ).distinct()

    def perform_create(self, serializer):
        serializer.save(requester=self.request.user)


class TransportBidViewSet(viewsets.ModelViewSet):
    queryset = TransportBid.objects.all()
    serializer_class = TransportBidSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        # A transporter sees their own bids; a requester sees bids placed
        # on their requests.
        user = self.request.user
        return TransportBid.objects.filter(
            Q(transporter=user) | Q(transport_request__requester=user)
        ).distinct()

    def perform_create(self, serializer):
        serializer.save(transporter=self.request.user)
