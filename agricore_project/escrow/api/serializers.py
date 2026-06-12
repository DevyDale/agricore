from rest_framework import serializers
from escrow.models import Escrow, PayoutAccount


class EscrowSerializer(serializers.ModelSerializer):
    class Meta:
        model = Escrow
        fields = "__all__"
        extra_kwargs = {
            "buyer": {"read_only": True},
            "status": {"read_only": True},
            "funded_at": {"read_only": True},
            "released_at": {"read_only": True},
        }


class PayoutAccountSerializer(serializers.ModelSerializer):
    class Meta:
        model = PayoutAccount
        fields = "__all__"
        extra_kwargs = {"user": {"read_only": True}}
