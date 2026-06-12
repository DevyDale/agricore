from rest_framework.routers import DefaultRouter
from .views import FarmViewSet, FieldViewSet

router = DefaultRouter()
router.register(r'farms', FarmViewSet, basename='farm')
router.register(r'fields', FieldViewSet, basename='field')

urlpatterns = router.urls
