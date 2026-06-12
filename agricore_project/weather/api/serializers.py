from rest_framework import serializers

from weather.models import WeatherSnapshot


class WeatherSnapshotSerializer(serializers.ModelSerializer):
    farm_name = serializers.CharField(source="farm.name", read_only=True)
    current = serializers.SerializerMethodField()
    daily = serializers.SerializerMethodField()
    units = serializers.SerializerMethodField()

    class Meta:
        model = WeatherSnapshot
        fields = [
            "farm",
            "farm_name",
            "latitude",
            "longitude",
            "location_name",
            "current",
            "daily",
            "units",
            "fetched_at",
        ]
        read_only_fields = fields

    def get_current(self, obj):
        return (obj.data or {}).get("current", {})

    def get_daily(self, obj):
        return (obj.data or {}).get("daily", {})

    def get_units(self, obj):
        return (obj.data or {}).get("units", {})
