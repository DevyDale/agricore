from rest_framework import serializers
from marketprices.models import MarketPrice


class MarketPriceSerializer(serializers.ModelSerializer):
    class Meta:
        model = MarketPrice
        fields = "__all__"
