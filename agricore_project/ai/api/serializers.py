from rest_framework import serializers
from ai.models import AILog, Alert

class AILogSerializer(serializers.ModelSerializer):
    class Meta:
        model = AILog
        fields = '__all__'
        read_only_fields = ['user', 'created_at']



class AlertSerializer(serializers.ModelSerializer):
    class Meta:
        model = Alert
        fields = '__all__'