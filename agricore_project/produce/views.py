# produce/views.py

from django.shortcuts import get_object_or_404
from rest_framework import viewsets, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework import status
import logging
from django.db.models import Sum


from farms.models import Farm
from .models import ProduceCollection
from .serializers import ProduceCollectionSerializer

# Note: Removed storage_location and estimated_value fields from model and serializer


class IsFarmOwner(permissions.BasePermission):
    def has_object_permission(self, request, view, obj):
        return obj.farm.owner == request.user


class ProduceCollectionViewSet(viewsets.ModelViewSet):
    serializer_class = ProduceCollectionSerializer
    permission_classes = [permissions.IsAuthenticated, IsFarmOwner]

    def get_queryset(self):
        farm_id = self.kwargs.get('farm_pk')
        if not farm_id:
            return ProduceCollection.objects.none()

        farm = get_object_or_404(Farm, id=farm_id, owner=self.request.user)
        return ProduceCollection.objects.filter(farm=farm)

    def perform_create(self, serializer):
        farm_id = self.kwargs.get('farm_pk')
        farm = get_object_or_404(Farm, id=farm_id, owner=self.request.user)
        serializer.save(farm=farm)

    def perform_update(self, serializer):
        farm_id = self.kwargs.get('farm_pk')
        farm = get_object_or_404(Farm, id=farm_id, owner=self.request.user)
        serializer.save(farm=farm)

    def create(self, request, *args, **kwargs):
        """Override create() to ensure serializer errors are logged and to make sure `farm` is read-only."""
        serializer = self.get_serializer(data=request.data)
        if not serializer.is_valid():
            logger = logging.getLogger(__name__)
            logger.error("Produce collection create validation error: %s", serializer.errors)
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        # Save with farm from URL
        farm_id = self.kwargs.get('farm_pk')
        farm = get_object_or_404(Farm, id=farm_id, owner=self.request.user)
        serializer.save(farm=farm)
        headers = self.get_success_headers(serializer.data)
        return Response(serializer.data, status=status.HTTP_201_CREATED, headers=headers)

    @action(detail=False, methods=['get'])
    def summary(self, request, farm_pk=None):
        farm = get_object_or_404(Farm, id=farm_pk, owner=request.user)

        qs = ProduceCollection.objects.filter(farm=farm)
        total_qty = qs.aggregate(total=Sum('quantity'))['total'] or 0

        last_collection = (
            qs.order_by('-collection_date').first().collection_date
            if qs.exists()
            else None
        )

        return Response({
            'total_collections': qs.count(),
            'total_quantity': float(total_qty),
            'last_collection': last_collection
        })