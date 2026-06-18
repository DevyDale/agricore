from rest_framework import serializers
from escrow.models import Escrow, PayoutAccount


class EscrowSerializer(serializers.ModelSerializer):
    def to_representation(self, instance):
        data = super().to_representation(instance)
        request = self.context.get("request")
        viewer = getattr(request, "user", None)
        # The delivery OTP is the buyer's proof of receipt -- never expose it to the seller.
        if not (viewer is not None and getattr(instance, "buyer_id", None) == getattr(viewer, "id", None)):
            data.pop("delivery_otp", None)
        return data

    class Meta:
        model = Escrow
        fields = "__all__"
        extra_kwargs = {
            "buyer": {"read_only": True},
            "status": {"read_only": True},
            "funded_at": {"read_only": True},
            "released_at": {"read_only": True},
            "delivery_otp": {"read_only": True},
            "otp_issued_at": {"read_only": True},
            "delivered_confirmed_at": {"read_only": True},
            "dispute_deadline": {"read_only": True},
            "dispute_reason": {"read_only": True},
            "dispatch_quantity": {"read_only": True},
            "dispatch_note": {"read_only": True},
            "dispatch_photo": {"read_only": True},
            "dispute_quantity": {"read_only": True},
            "dispute_photo": {"read_only": True},
        }


class PayoutAccountSerializer(serializers.ModelSerializer):
    def validate(self, attrs):
        """Validate a seller payout destination at save time so payouts do not
        silently fail later. Normalizes Ugandan mobile numbers and infers the
        network; bank payouts must carry a bank code."""
        inst = getattr(self, "instance", None)

        def cur(key, default=""):
            if key in attrs:
                return attrs.get(key)
            return getattr(inst, key, default) if inst is not None else default

        method = (cur("method", "momo") or "momo").lower()
        name = (cur("account_name", "") or "").strip()
        if not name:
            raise serializers.ValidationError({"account_name": "Account holder name is required."})
        number = (cur("account_number", "") or "").strip()

        if method == "momo":
            from utils.sms import normalize_ug
            norm = normalize_ug(number)
            digits = norm[1:] if norm.startswith("+") else norm
            if not (norm.startswith("+256") and len(digits) == 12 and digits[3] == "7"):
                raise serializers.ValidationError(
                    {"account_number": "Enter a valid Ugandan mobile money number, e.g. 0772123456."}
                )
            attrs["account_number"] = norm
            if not (cur("account_bank", "") or "").strip():
                attrs["account_bank"] = "MPS"
            if not (cur("network", "") or "").strip():
                pref = digits[3:5]
                if pref in {"77", "78", "76"}:
                    attrs["network"] = "MTN"
                elif pref in {"70", "75", "74"}:
                    attrs["network"] = "AIRTEL"
        else:
            if not number:
                raise serializers.ValidationError({"account_number": "Bank account number is required."})
            code = (cur("account_bank", "") or "").strip()
            if not code:
                raise serializers.ValidationError({"account_bank": "Bank code is required for bank payouts."})
            from utils import flutterwave
            try:
                valid_codes = {b["code"] for b in flutterwave.list_banks("UG")}
            except flutterwave.FlutterwaveError:
                valid_codes = set()
            if valid_codes and code not in valid_codes:
                raise serializers.ValidationError(
                    {"account_bank": "Select a valid bank from the list."}
                )
            attrs["account_bank"] = code
        return attrs

    class Meta:
        model = PayoutAccount
        fields = "__all__"
        extra_kwargs = {"user": {"read_only": True}}
