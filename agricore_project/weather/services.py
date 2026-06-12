"""Weather data via Open-Meteo (free, no API key required).

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
