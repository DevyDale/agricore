from django.contrib import admin

from .models import WeatherSnapshot


@admin.register(WeatherSnapshot)
class WeatherSnapshotAdmin(admin.ModelAdmin):
    list_display = ("farm", "location_name", "latitude", "longitude", "fetched_at")
    search_fields = ("farm__name", "location_name")
    readonly_fields = ("fetched_at",)
