from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from livestock.models import LivestockUnit, Animal, AnimalReproductiveRecord, LivestockTask, LivestockEmployeeAssignment, LivestockExpense, AnimalMedicalRecord
from .serializers import LivestockUnitSerializer, AnimalSerializer, AnimalReproductiveRecordSerializer, LivestockTaskSerializer, LivestockEmployeeAssignmentSerializer, LivestockExpenseSerializer, AnimalMedicalRecordSerializer

class LivestockUnitViewSet(viewsets.ModelViewSet):
    queryset = LivestockUnit.objects.all()
    serializer_class = LivestockUnitSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(field__farm__owner=self.request.user)

class AnimalViewSet(viewsets.ModelViewSet):
    queryset = Animal.objects.all()
    serializer_class = AnimalSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(livestock_unit__field__farm__owner=self.request.user)

class AnimalReproductiveRecordViewSet(viewsets.ModelViewSet):
    queryset = AnimalReproductiveRecord.objects.all()
    serializer_class = AnimalReproductiveRecordSerializer
    permission_classes = [IsAuthenticated]

class LivestockTaskViewSet(viewsets.ModelViewSet):
    queryset = LivestockTask.objects.all()
    serializer_class = LivestockTaskSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(livestock_unit__field__farm__owner=self.request.user)

class LivestockEmployeeAssignmentViewSet(viewsets.ModelViewSet):
    queryset = LivestockEmployeeAssignment.objects.all()
    serializer_class = LivestockEmployeeAssignmentSerializer
    permission_classes = [IsAuthenticated]

class LivestockExpenseViewSet(viewsets.ModelViewSet):
    queryset = LivestockExpense.objects.all()
    serializer_class = LivestockExpenseSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(livestock_unit__field__farm__owner=self.request.user)

class AnimalMedicalRecordViewSet(viewsets.ModelViewSet):
    queryset = AnimalMedicalRecord.objects.all()
    serializer_class = AnimalMedicalRecordSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(livestock_unit__field__farm__owner=self.request.user)