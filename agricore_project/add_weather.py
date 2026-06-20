#!/usr/bin/env python3
"""
add_weather.py  --  Adds a self-contained `weather` app to Agricore.

What it does (idempotent, all-or-nothing patches with backups):
  1. Creates the `weather` Django app (models, services, admin, API view/serializer).
     - Open-Meteo (FREE, no API key). Geocodes farm.city/country -> coordinates,
       so your core Farm model is NOT touched.
     - One cached WeatherSnapshot per farm, refreshed when stale.
  2. Registers `weather` in INSTALLED_APPS + adds WEATHER_CACHE_MINUTES setting.
  3. Adds the route  GET /api/weather/  (owner-scoped).
  4. Wires real weather into ai/tasks.generate_daily_predictions (replaces the
     {"temperature": 25, "rainfall": 10} placeholder, with a safe fallback).

Run from the folder that contains manage.py:
    python add_weather.py
Then:
    python manage.py makemigrations weather
    python manage.py migrate
    python manage.py check
"""
import os
import sys
import shutil
from datetime import datetime

# --------------------------------------------------------------------------
# Locate the project (the dir containing manage.py)
# --------------------------------------------------------------------------
HERE = os.path.abspath(os.path.dirname(__file__))
if not os.path.exists(os.path.join(HERE, "manage.py")):
    # maybe run from repo root with backend nested
    cand = os.path.join(HERE, "agricore_project")
    if os.path.exists(os.path.join(cand, "manage.py")):
        HERE = cand
    else:
        sys.exit("ERROR: run this from the folder that has manage.py")

BASE = HERE


def find_file(rel):
    """Direct path first, then walk (skipping hidden dirs)."""
    direct = os.path.join(BASE, rel)
    if os.path.exists(direct):
        return direct
    target = os.path.basename(rel)
    for root, dirs, files in os.walk(BASE):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        if target in files and rel.replace("/", os.sep) in os.path.join(root, target):
            return os.path.join(root, target)
    return None


SETTINGS = find_file("agricore_project/settings.py")
URLS = find_file("agricore_project/urls.py")
TASKS = find_file("ai/tasks.py")

for label, p in [("settings.py", SETTINGS), ("urls.py", URLS), ("ai/tasks.py", TASKS)]:
    if not p:
        sys.exit(f"ERROR: could not locate {label}")

# --------------------------------------------------------------------------
# File contents for the new `weather` app
# --------------------------------------------------------------------------
APP_FILES = {}

APP_FILES["weather/__init__.py"] = ""

APP_FILES["weather/apps.py"] = '''from django.apps import AppConfig


class WeatherConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "weather"
'''

APP_FILES["weather/models.py"] = '''from django.db import models


class WeatherSnapshot(models.Model):
    """Latest cached weather for a farm (one row per farm, refreshed in place)."""

    farm = models.OneToOneField(
        "farms.Farm", on_delete=models.CASCADE, related_name="weather"
    )
    latitude = models.DecimalField(max_digits=9, decimal_places=5, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=5, null=True, blank=True)
    location_name = models.CharField(max_length=255, blank=True)
    data = models.JSONField(default=dict, blank=True)
    fetched_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-fetched_at"]

    def __str__(self):
        return f"Weather for farm {self.farm_id} ({self.location_name or 'unknown'})"
'''

APP_FILES["weather/admin.py"] = '''from django.contrib import admin

from .models import WeatherSnapshot


@admin.register(WeatherSnapshot)
class WeatherSnapshotAdmin(admin.ModelAdmin):
    list_display = ("farm", "location_name", "latitude", "longitude", "fetched_at")
    search_fields = ("farm__name", "location_name")
    readonly_fields = ("fetched_at",)
'''

APP_FILES["weather/services.py"] = '''"""Weather data via Open-Meteo (free, no API key required).

Geocodes a farm's city/country to coordinates, fetches current + 7-day
forecast, and caches one snapshot per farm. All network calls live here so the
rest of the app stays offline-friendly and testable.
"""
from datetime import timedelta

import requests
from django.conf import settings
from django.utils import timezone

from .models import WeatherSnapshot

GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

CURRENT_FIELDS = (
    "temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_speed_10m"
)
DAILY_FIELDS = "temperature_2m_max,temperature_2m_min,precipitation_sum,weather_code"


class WeatherError(Exception):
    """Raised when a location cannot be resolved or the forecast is unusable."""


def _ttl_minutes():
    return getattr(settings, "WEATHER_CACHE_MINUTES", 60)


def geocode(city, country=""):
    """Resolve a place name to (lat, lon, label) using Open-Meteo geocoding."""
    params = {"name": city, "count": 1, "language": "en", "format": "json"}
    resp = requests.get(GEOCODE_URL, params=params, timeout=10)
    resp.raise_for_status()
    results = (resp.json() or {}).get("results") or []
    if not results:
        raise WeatherError(f"Could not find coordinates for '{city}'.")
    top = results[0]
    label = ", ".join(p for p in (top.get("name"), top.get("country")) if p)
    return float(top["latitude"]), float(top["longitude"]), label


def fetch_forecast(lat, lon):
    """Fetch current conditions + 7-day daily forecast for coordinates."""
    params = {
        "latitude": lat,
        "longitude": lon,
        "current": CURRENT_FIELDS,
        "daily": DAILY_FIELDS,
        "forecast_days": 7,
        "timezone": "auto",
    }
    resp = requests.get(FORECAST_URL, params=params, timeout=10)
    resp.raise_for_status()
    payload = resp.json() or {}
    return {
        "current": payload.get("current", {}),
        "daily": payload.get("daily", {}),
        "units": {
            "current": payload.get("current_units", {}),
            "daily": payload.get("daily_units", {}),
        },
    }


def get_farm_weather(farm, lat=None, lon=None, force=False):
    """Return a fresh-or-cached WeatherSnapshot for a farm.

    Coordinate resolution order: explicit lat/lon override > previously stored
    snapshot coords > geocode from farm.city/country.
    """
    snap = WeatherSnapshot.objects.filter(farm=farm).first()
    override = lat is not None and lon is not None

    # Fast path: reuse a fresh snapshot when nothing forces a refetch.
    if snap and snap.data and not force and not override:
        if (timezone.now() - snap.fetched_at) < timedelta(minutes=_ttl_minutes()):
            return snap

    if override:
        latitude, longitude = float(lat), float(lon)
        location_name = snap.location_name if snap else ""
    elif snap and snap.latitude is not None and snap.longitude is not None:
        latitude, longitude = float(snap.latitude), float(snap.longitude)
        location_name = snap.location_name
    else:
        if not getattr(farm, "city", None):
            raise WeatherError(
                "This farm has no city set. Add a city to the farm or pass lat/lon."
            )
        latitude, longitude, location_name = geocode(
            farm.city, getattr(farm, "country", "") or ""
        )

    data = fetch_forecast(latitude, longitude)
    snap, _ = WeatherSnapshot.objects.update_or_create(
        farm=farm,
        defaults={
            "latitude": latitude,
            "longitude": longitude,
            "location_name": location_name,
            "data": data,
        },
    )
    return snap


def weather_summary_for_ai(farm):
    """Compact weather dict for AI grounding, or None if unavailable.

    Never raises -- callers can safely fall back to placeholder inputs.
    """
    try:
        snap = get_farm_weather(farm)
    except Exception:
        return None
    current = (snap.data or {}).get("current", {})
    return {
        "temperature_c": current.get("temperature_2m"),
        "humidity_pct": current.get("relative_humidity_2m"),
        "precipitation_mm": current.get("precipitation"),
        "wind_kmh": current.get("wind_speed_10m"),
        "location": snap.location_name,
    }
'''

APP_FILES["weather/migrations/__init__.py"] = ""
APP_FILES["weather/api/__init__.py"] = ""

APP_FILES["weather/api/serializers.py"] = '''from rest_framework import serializers

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
'''

APP_FILES["weather/api/views.py"] = '''import requests
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
'''

# --------------------------------------------------------------------------
# Validate-all-then-write-all
# --------------------------------------------------------------------------
print("Agricore weather feature installer")
print("=" * 60)
print(f"Project: {BASE}\n")

# Read the three files we will patch.
with open(SETTINGS, encoding="utf-8") as f:
    settings_src = f.read()
with open(URLS, encoding="utf-8") as f:
    urls_src = f.read()
with open(TASKS, encoding="utf-8") as f:
    tasks_src = f.read()

# Patch anchors / guards
APPS_ANCHOR = "    'notifications.apps.NotificationsConfig',\n"
APPS_INSERT = "    'weather.apps.WeatherConfig',\n"
APPS_DONE = "weather.apps.WeatherConfig" in settings_src

SETTING_GUARD = "WEATHER_CACHE_MINUTES" in settings_src
SETTING_BLOCK = (
    "\n\n# --- Weather (Open-Meteo) snapshot cache TTL in minutes ---\n"
    "WEATHER_CACHE_MINUTES = env.int('WEATHER_CACHE_MINUTES', default=60)\n"
)

URL_IMPORT_ANCHOR = (
    "from drf_spectacular.views import "
    "SpectacularAPIView, SpectacularSwaggerView, SpectacularRedocView\n"
)
URL_IMPORT_INSERT = "from weather.api.views import FarmWeatherView\n"
URL_IMPORT_DONE = "from weather.api.views import FarmWeatherView" in urls_src

URL_ROUTE_ANCHOR = (
    "    path('api/users/me/', CurrentUserView.as_view(), name='current_user'),\n"
)
URL_ROUTE_INSERT = (
    "\n    # Weather (per-farm, Open-Meteo)\n"
    "    path('api/weather/', FarmWeatherView.as_view(), name='farm-weather'),\n"
)
URL_ROUTE_DONE = "name='farm-weather'" in urls_src

TASKS_ANCHOR = (
    '        inputs = {"temperature": 25, "rainfall": 10}'
    "  # TODO: pull latest EnvironmentalData\n"
)
TASKS_INSERT = (
    "        try:\n"
    "            from weather.services import weather_summary_for_ai\n"
    "            _w = weather_summary_for_ai(farm)\n"
    "            inputs = _w if _w else {\"temperature\": 25, \"rainfall\": 10}\n"
    "        except Exception:\n"
    "            inputs = {\"temperature\": 25, \"rainfall\": 10}\n"
)
TASKS_DONE = "weather_summary_for_ai" in tasks_src

# Validate anchors exist (unless already applied).
errors = []
if not APPS_DONE and APPS_ANCHOR not in settings_src:
    errors.append("INSTALLED_APPS anchor (notifications line) not found in settings.py")
if not URL_IMPORT_DONE and URL_IMPORT_ANCHOR not in urls_src:
    errors.append("urls.py import anchor (drf_spectacular.views) not found")
if not URL_ROUTE_DONE and URL_ROUTE_ANCHOR not in urls_src:
    errors.append("urls.py route anchor (api/users/me/) not found")
if not TASKS_DONE and TASKS_ANCHOR not in tasks_src:
    errors.append("ai/tasks.py placeholder-inputs anchor not found")

if errors:
    print("ABORTED -- anchors did not match (no files changed):")
    for e in errors:
        print("  - " + e)
    sys.exit(1)

# --------------------------------------------------------------------------
# Apply
# --------------------------------------------------------------------------
backup_dir = os.path.join(BASE, ".weather_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S"))

# 1. Create app files (write-if-absent so re-runs don't clobber edits).
created, skipped = [], []
for rel, content in APP_FILES.items():
    path = os.path.join(BASE, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        skipped.append(rel)
        continue
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    created.append(rel)

# 2/3/4. Patch the three existing files (back up first).
def backup(path):
    os.makedirs(backup_dir, exist_ok=True)
    shutil.copy2(path, os.path.join(backup_dir, os.path.basename(path)))

patches = []

new_settings = settings_src
if not APPS_DONE:
    new_settings = new_settings.replace(APPS_ANCHOR, APPS_ANCHOR + APPS_INSERT, 1)
    patches.append("settings.py: registered weather in INSTALLED_APPS")
if not SETTING_GUARD:
    new_settings = new_settings.rstrip("\n") + "\n" + SETTING_BLOCK
    patches.append("settings.py: added WEATHER_CACHE_MINUTES")
if new_settings != settings_src:
    backup(SETTINGS)
    with open(SETTINGS, "w", encoding="utf-8") as f:
        f.write(new_settings)

new_urls = urls_src
if not URL_IMPORT_DONE:
    new_urls = new_urls.replace(URL_IMPORT_ANCHOR, URL_IMPORT_ANCHOR + URL_IMPORT_INSERT, 1)
    patches.append("urls.py: imported FarmWeatherView")
if not URL_ROUTE_DONE:
    new_urls = new_urls.replace(URL_ROUTE_ANCHOR, URL_ROUTE_ANCHOR + URL_ROUTE_INSERT, 1)
    patches.append("urls.py: added /api/weather/ route")
if new_urls != urls_src:
    backup(URLS)
    with open(URLS, "w", encoding="utf-8") as f:
        f.write(new_urls)

new_tasks = tasks_src
if not TASKS_DONE:
    new_tasks = new_tasks.replace(TASKS_ANCHOR, TASKS_INSERT, 1)
    patches.append("ai/tasks.py: AI predictions now use live weather (with fallback)")
if new_tasks != tasks_src:
    backup(TASKS)
    with open(TASKS, "w", encoding="utf-8") as f:
        f.write(new_tasks)

# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------
print("App files created:")
for r in created:
    print("  + " + r)
if skipped:
    print("App files already present (left as-is):")
    for r in skipped:
        print("  = " + r)
print()
if patches:
    print("Patches applied:")
    for p in patches:
        print("  * " + p)
else:
    print("No patches needed -- everything was already in place.")
if os.path.exists(backup_dir):
    print(f"\nBackups of edited files: {backup_dir}")

print("\nNext steps:")
print("  python manage.py makemigrations weather")
print("  python manage.py migrate")
print("  python manage.py check")
print("\nThen test live (replace <id> and <token>):")
print("  curl -H \"Authorization: Bearer <token>\" "
      "\"http://127.0.0.1:8000/api/weather/?farm=<id>\"")
