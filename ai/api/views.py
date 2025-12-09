from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from ai.models import AILog, Prediction, Alert
from .serializers import AILogSerializer, PredictionSerializer, AlertSerializer

class AILogViewSet(viewsets.ModelViewSet):
    queryset = AILog.objects.all()
    serializer_class = AILogSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

class PredictionViewSet(viewsets.ModelViewSet):
    queryset = Prediction.objects.all()
    serializer_class = PredictionSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)

class AlertViewSet(viewsets.ModelViewSet):
    queryset = Alert.objects.all()
    serializer_class = AlertSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)