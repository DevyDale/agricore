

from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .api.views import CropCycleViewSet

app_name = "crops"

router = DefaultRouter()
router.register(r'crop-cycles', CropCycleViewSet, basename='cropcycle')

urlpatterns = [
	path('api/', include(router.urls)),
]
