from rest_framework import serializers
from logistics.models import Vehicle, TransportRequest, TransportBid


class VehicleSerializer(serializers.ModelSerializer):
    class Meta:
        model = Vehicle
        fields = "__all__"
        extra_kwargs = {"transporter": {"read_only": True}}


class TransportRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = TransportRequest
        fields = "__all__"
        extra_kwargs = {"requester": {"read_only": True}}


class TransportBidSerializer(serializers.ModelSerializer):
    class Meta:
        model = TransportBid
        fields = "__all__"
        extra_kwargs = {"transporter": {"read_only": True}}
