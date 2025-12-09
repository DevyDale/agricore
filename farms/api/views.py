from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from rest_framework.exceptions import ValidationError
from farms.models import Farm, Field, EnvironmentalData
from farms.api.serializers import FarmSerializer, FieldSerializer, EnvironmentalDataSerializer
import logging

logger = logging.getLogger(__name__)

class FarmViewSet(viewsets.ModelViewSet):
    queryset = Farm.objects.all()
    serializer_class = FarmSerializer
    permission_classes = [IsAuthenticated]

    def create(self, request, *args, **kwargs):
        logger.info(f"FarmViewSet: Received POST request with data: {request.data}")
        try:
            response = super().create(request, *args, **kwargs)
            logger.info(f"FarmViewSet: Response: {response.data}")
            return response
        except ValidationError as e:
            logger.error(f"FarmViewSet: Validation error: {e}")
            raise
        except Exception as e:
            logger.error(f"FarmViewSet: Unexpected error: {e}")
            raise

class FieldViewSet(viewsets.ModelViewSet):
    queryset = Field.objects.all()
    serializer_class = FieldSerializer
    permission_classes = [IsAuthenticated]

    def create(self, request, *args, **kwargs):
        logger.info(f"FieldViewSet: Received POST request with data: {request.data}")
        try:
            response = super().create(request, *args, **kwargs)
            logger.info(f"FieldViewSet: Response: {response.data}")
            return response
        except ValidationError as e:
            logger.error(f"FieldViewSet: Validation error: {e}")
            raise
        except Exception as e:
            logger.error(f"FieldViewSet: Unexpected error: {e}")
            raise

class EnvironmentalDataViewSet(viewsets.ModelViewSet):
    queryset = EnvironmentalData.objects.all()
    serializer_class = EnvironmentalDataSerializer
    permission_classes = [IsAuthenticated]

    def create(self, request, *args, **kwargs):
        logger.info(f"EnvironmentalDataViewSet: Received POST request with data: {request.data}")
        try:
            response = super().create(request, *args, **kwargs)
            logger.info(f"EnvironmentalDataViewSet: Response: {response.data}")
            return response
        except ValidationError as e:
            logger.error(f"EnvironmentalDataViewSet: Validation error: {e}")
            raise
        except Exception as e:
            logger.error(f"EnvironmentalDataViewSet: Unexpected error: {e}")
            raise
