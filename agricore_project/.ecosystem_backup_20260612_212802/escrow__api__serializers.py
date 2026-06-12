from rest_framework import serializers
from escrow.models import Escrow


class EscrowSerializer(serializers.ModelSerializer):
    class Meta:
        model = Escrow
        fields = "__all__"
        extra_kwargs = {
            "buyer": {"read_only": True},
            "funded_at": {"read_only": True},
            "released_at": {"read_only": True},
        }
