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


from rest_framework import serializers
from logistics.models import Transporter, DeliveryJob, TransporterReview


class TransporterSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source="user.username", read_only=True)

    class Meta:
        model = Transporter
        fields = "__all__"
        extra_kwargs = {
            "user": {"read_only": True},
            "is_verified": {"read_only": True},
            "rating_avg": {"read_only": True},
            "rating_count": {"read_only": True},
            "deposit_balance": {"read_only": True},
        }


class DeliveryJobSerializer(serializers.ModelSerializer):
    seller_name = serializers.SerializerMethodField()
    seller_phone = serializers.SerializerMethodField()

    def get_seller_name(self, obj):
        store = getattr(obj.order, "store", None)
        if not store:
            return ""
        return getattr(store, "owner_name", "") or getattr(store, "name", "") or ""

    def get_seller_phone(self, obj):
        store = getattr(obj.order, "store", None)
        return (getattr(store, "owner_phone", "") or "") if store else ""

    class Meta:
        model = DeliveryJob
        fields = "__all__"
        extra_kwargs = {
            "created_by": {"read_only": True},
            "transporter": {"read_only": True},
            "status": {"read_only": True},
            "pickup_code": {"read_only": True},
            "escrow": {"read_only": True},
            "accepted_at": {"read_only": True},
            "picked_up_at": {"read_only": True},
            "delivered_at": {"read_only": True},
        }

    def to_representation(self, instance):
        data = super().to_representation(instance)
        request = self.context.get("request")
        viewer = getattr(request, "user", None)
        # The pickup code is the seller's handover proof -- hide it from the rider/others.
        _vid = getattr(viewer, "id", None)
        _is_creator = getattr(instance, "created_by_id", None) == _vid
        _is_rider = bool(getattr(instance, "transporter_id", None) and instance.transporter.user_id == _vid)
        if not _is_creator:
            data.pop("pickup_code", None)
        # Seller contact is shared only with the seller and the assigned rider.
        if not (_is_creator or _is_rider):
            data.pop("seller_name", None)
            data.pop("seller_phone", None)
        return data


class TransporterReviewSerializer(serializers.ModelSerializer):
    class Meta:
        model = TransporterReview
        fields = "__all__"
        extra_kwargs = {"by_user": {"read_only": True}}
