# farms/api/views.py (Assumed contents)

from rest_framework import viewsets, permissions
from rest_framework.authentication import TokenAuthentication # Or SessionAuthentication/JWTAuth
from rest_framework.response import Response
from rest_framework import status
import logging
from ..models import Farm, Field
from .serializers import FarmSerializer, FieldSerializer

# ViewSet for Field (Land Portion)
class FieldViewSet(viewsets.ModelViewSet):
    serializer_class = FieldSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        # Only return fields for farms owned by the user
        return Field.objects.filter(farm__owner=self.request.user)

    def perform_create(self, serializer):
        # Ensure the field is linked to a farm owned by the user
        farm = serializer.validated_data.get('farm')
        if farm.owner != self.request.user:
            raise PermissionError('You do not own this farm.')
        serializer.save()

class FarmViewSet(viewsets.ModelViewSet):
    # Ensure this queryset is correct for listing farms
    queryset = Farm.objects.all()
    serializer_class = FarmSerializer
    
    # 1. AUTHENTICATION: Ensure the user is logged in
    # This might use permissions.IsAuthenticated or a custom permission
    permission_classes = [permissions.IsAuthenticated] 
    
    # 2. FILTERING: Ensure users only see their own farms (best practice)
    def get_queryset(self):
        # Only return farms owned by the requesting user
        return Farm.objects.filter(owner=self.request.user)
    
    # 3. CRITICAL FIX: The `perform_create` method
    # This method is essential for setting the read-only 'owner' field
    # which is derived from the current request's user.
    def perform_create(self, serializer):
        # The serializer.save() call adds the current user as the owner
        # This prevents the 400 Bad Request due to missing NOT NULL database constraint on owner.
        serializer.save(owner=self.request.user)

    def create(self, request, *args, **kwargs):
        """Override create() to log validation errors and return detailed responses.

        This helps with debugging 400 errors during development since serializer
        errors can be logged to the server logs and returned to the client.
        """
        serializer = self.get_serializer(data=request.data)
        if not serializer.is_valid():
            logger = logging.getLogger(__name__)
            logger.error("Farm creation validation error: %s", serializer.errors)
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        self.perform_create(serializer)
        headers = self.get_success_headers(serializer.data)
        return Response(serializer.data, status=status.HTTP_201_CREATED, headers=headers)

    # Note: perform_update and perform_destroy should also be present
    # if you want to enforce ownership checks, but perform_create is the key for the POST error.