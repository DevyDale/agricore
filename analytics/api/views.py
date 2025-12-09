from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from analytics.models import AnalyticsAggregate, Report, FarmFinance
from .serializers import AnalyticsAggregateSerializer, ReportSerializer, FarmFinanceSerializer

class AnalyticsAggregateViewSet(viewsets.ModelViewSet):
    queryset = AnalyticsAggregate.objects.all()
    serializer_class = AnalyticsAggregateSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)

class ReportViewSet(viewsets.ModelViewSet):
    queryset = Report.objects.all()
    serializer_class = ReportSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)

class FarmFinanceViewSet(viewsets.ModelViewSet):
    queryset = FarmFinance.objects.all()
    serializer_class = FarmFinanceSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)