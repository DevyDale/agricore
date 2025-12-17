from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from inventory.models import Inventory, ProductionRecord
from .serializers import InventorySerializer, ProductionRecordSerializer

class InventoryViewSet(viewsets.ModelViewSet):
    queryset = Inventory.objects.all()
    serializer_class = InventorySerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)

class ProductionRecordViewSet(viewsets.ModelViewSet):
    queryset = ProductionRecord.objects.all()
    serializer_class = ProductionRecordSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)