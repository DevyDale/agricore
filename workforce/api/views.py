from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from workforce.models import Employee, Machinery, Equipment, EmployeePerformance, FiredEmployee
from .serializers import EmployeeSerializer, MachinerySerializer, EquipmentSerializer, EmployeePerformanceSerializer, FiredEmployeeSerializer

class EmployeeViewSet(viewsets.ModelViewSet):
    queryset = Employee.objects.all()
    serializer_class = EmployeeSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)

class MachineryViewSet(viewsets.ModelViewSet):
    queryset = Machinery.objects.all()
    serializer_class = MachinerySerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)

class EquipmentViewSet(viewsets.ModelViewSet):
    queryset = Equipment.objects.all()
    serializer_class = EquipmentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)

class EmployeePerformanceViewSet(viewsets.ModelViewSet):
    queryset = EmployeePerformance.objects.all()
    serializer_class = EmployeePerformanceSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(employee__farm__owner=self.request.user)

class FiredEmployeeViewSet(viewsets.ModelViewSet):
    queryset = FiredEmployee.objects.all()
    serializer_class = FiredEmployeeSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)