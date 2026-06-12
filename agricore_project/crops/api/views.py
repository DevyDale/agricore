
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from .serializers import CropCycleSerializer
from ..models import CropCycle

class CropCycleViewSet(viewsets.ModelViewSet):
	queryset = CropCycle.objects.all()
	serializer_class = CropCycleSerializer
	permission_classes = [IsAuthenticated]








