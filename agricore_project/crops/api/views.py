
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from .serializers import CropCycleSerializer
from ..models import CropCycle

class CropCycleViewSet(viewsets.ModelViewSet):
	queryset = CropCycle.objects.all()
	serializer_class = CropCycleSerializer
	permission_classes = [IsAuthenticated]

	def get_queryset(self):
		from django.db.models import Q
		user = self.request.user
		# Cycles on the user's farms, plus unassigned units (field is null)
		return self.queryset.filter(
			Q(crop_unit__field__farm__owner=user) | Q(crop_unit__field__isnull=True)
		)
