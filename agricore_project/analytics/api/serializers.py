from rest_framework import serializers
from analytics.models import AnalyticsAggregate, Report, FarmFinance

class AnalyticsAggregateSerializer(serializers.ModelSerializer):
    class Meta:
        model = AnalyticsAggregate
        fields = '__all__'

class ReportSerializer(serializers.ModelSerializer):
    class Meta:
        model = Report
        fields = '__all__'

class FarmFinanceSerializer(serializers.ModelSerializer):
    class Meta:
        model = FarmFinance
        fields = '__all__'