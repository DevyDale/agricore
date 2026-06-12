import requests
from drf_spectacular.utils import extend_schema, OpenApiParameter
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from farms.models import Farm
from weather import services
from weather.api.serializers import WeatherSnapshotSerializer


class FarmWeatherView(APIView):
    """Current conditions + 7-day forecast for the caller's farm(s)."""

    permission_classes = [IsAuthenticated]

    @extend_schema(
        summary="Get weather for your farm(s)",
        description=(
            "Returns current conditions and a 7-day forecast for a farm you own. "
            "Pass ?farm=<id> for one farm, or omit it to get every farm you own. "
            "Use ?refresh=1 to force a refetch, and ?lat=&lon= to override the "
            "location (e.g. from a map picker)."
        ),
        parameters=[
            OpenApiParameter("farm", int, description="Farm id (must be owned by you)."),
            OpenApiParameter("refresh", str, description="Set to 1 to force a refresh."),
            OpenApiParameter("lat", str, description="Latitude override (optional)."),
            OpenApiParameter("lon", str, description="Longitude override (optional)."),
        ],
        responses=WeatherSnapshotSerializer,
    )
    def get(self, request):
        owned = Farm.objects.filter(owner=request.user)
        farm_id = request.query_params.get("farm")
        force = request.query_params.get("refresh") in ("1", "true", "True", "yes")
        lat = request.query_params.get("lat")
        lon = request.query_params.get("lon")

        if farm_id:
            farm = owned.filter(pk=farm_id).first()
            if farm is None:
                return Response({"detail": "Farm not found."}, status=404)
            try:
                snap = services.get_farm_weather(farm, lat=lat, lon=lon, force=force)
            except services.WeatherError as exc:
                return Response({"detail": str(exc)}, status=400)
            except requests.RequestException as exc:
                return Response(
                    {"detail": f"Weather service unavailable: {exc}"}, status=502
                )
            return Response(WeatherSnapshotSerializer(snap).data)

        # No farm id -> best-effort weather for all owned farms (cached only).
        out = []
        for farm in owned:
            try:
                snap = services.get_farm_weather(farm)
            except Exception:
                continue
            out.append(WeatherSnapshotSerializer(snap).data)
        return Response(out)
