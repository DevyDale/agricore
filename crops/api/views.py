from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from crops.models import Crop, CropTask, CropEmployeeAssignment, CropExpense
from .serializers import CropSerializer, CropTaskSerializer, CropEmployeeAssignmentSerializer, CropExpenseSerializer

class CropViewSet(viewsets.ModelViewSet):
    queryset = Crop.objects.all()
    serializer_class = CropSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(field__farm__owner=self.request.user)

class CropTaskViewSet(viewsets.ModelViewSet):
    queryset = CropTask.objects.all()
    serializer_class = CropTaskSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(crop__field__farm__owner=self.request.user)

class CropEmployeeAssignmentViewSet(viewsets.ModelViewSet):
    queryset = CropEmployeeAssignment.objects.all()
    serializer_class = CropEmployeeAssignmentSerializer
    permission_classes = [IsAuthenticated]

class CropExpenseViewSet(viewsets.ModelViewSet):
    queryset = CropExpense.objects.all()
    serializer_class = CropExpenseSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(crop__field__farm__owner=self.request.user)