from rest_framework import viewsets
from drf_spectacular.utils import extend_schema, inline_serializer, OpenApiResponse
from rest_framework import serializers
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated, AllowAny, BasePermission, SAFE_METHODS
from rest_framework_simplejwt.tokens import RefreshToken
from google.oauth2 import id_token
from google.auth.transport import requests
from django.conf import settings
from accounts.models import (
    CustomUser,
    Attachment,
    DigitalWallet,
    SpecializedProfessional,
    Review,
    OnboardingProgress,
)
from accounts.api.serializers import (
    CustomUserSerializer,
    AttachmentSerializer,
    DigitalWalletSerializer,
    SpecializedProfessionalSerializer,
    ReviewSerializer,
    OnboardingProgressSerializer,
)


class CurrentUserView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(responses=CustomUserSerializer)
    def get(self, request):
        # When called by an authenticated user, return their serialized profile.
        serializer = CustomUserSerializer(request.user)
        return Response(serializer.data)


class GoogleAuthView(APIView):
    permission_classes = [AllowAny]

    @extend_schema(request=inline_serializer(name="GoogleAuthRequest", fields={"token": serializers.CharField()}), responses=inline_serializer(name="GoogleAuthResponse", fields={"access": serializers.CharField(), "refresh": serializers.CharField(), "created": serializers.BooleanField(), "user": CustomUserSerializer()}))
    def post(self, request):
        token = request.data.get('token') or request.data.get('id_token')

        if not token:
            return Response(
                {'error': 'Token is required'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        allowed_auds = getattr(settings, 'GOOGLE_OAUTH_CLIENT_IDS', [])
        if not allowed_auds:
            return Response(
                {'error': 'Google sign-in is not configured on the server'},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        try:
            # Verify signature, issuer, and expiry against Google's public certs.
            # audience=None so we can accept several client IDs (Android / iOS /
            # web) and check the audience ourselves against the allow-list below.
            idinfo = id_token.verify_oauth2_token(
                token,
                requests.Request(),
                audience=None,
            )
        except ValueError as e:
            return Response(
                {'error': f'Invalid token: {str(e)}'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        # The token must have been issued for one of our own apps.
        if idinfo.get('aud') not in allowed_auds:
            return Response(
                {'error': 'Token audience is not allowed'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        # Only accept emails that Google itself has verified.
        if not idinfo.get('email_verified', False):
            return Response(
                {'error': 'Google account email is not verified'},
                status=status.HTTP_403_FORBIDDEN,
            )

        email = idinfo.get('email')
        google_id = idinfo.get('sub', '')
        name = idinfo.get('name', '')

        if not email:
            return Response(
                {'error': 'Email not provided by Google'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Match an existing account by email (links password + Google logins),
        # or create a new one. The email is Google-verified at this point.
        user, created = CustomUser.objects.get_or_create(
            email=email,
            defaults={
                'username': email.split('@')[0] + '_' + google_id[:8],
                'first_name': name.split()[0] if name else '',
                'last_name': ' '.join(name.split()[1:]) if len(name.split()) > 1 else '',
                'is_verified': True,
            },
        )

        # A successful Google login proves email ownership.
        if not user.is_verified:
            user.is_verified = True
            user.save(update_fields=['is_verified'])

        refresh = RefreshToken.for_user(user)

        return Response({
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'user': CustomUserSerializer(user).data,
            'created': created,
        }, status=status.HTTP_200_OK)


class IsOwnerOrReadOnly(BasePermission):
    """Read for any authenticated user; write only for the object's owner."""
    def has_object_permission(self, request, view, obj):
        if request.method in SAFE_METHODS:
            return True
        return getattr(obj, 'user_id', None) == request.user.id


class CustomUserViewSet(viewsets.ModelViewSet):
    queryset = CustomUser.objects.all()
    serializer_class = CustomUserSerializer

    def get_permissions(self):
        if self.action == 'create':
            return [AllowAny()]  # Allow unauthenticated POST
        return [IsAuthenticated()]  # Require auth for other actions

    def get_queryset(self):
        user = self.request.user
        if not user.is_authenticated:
            return CustomUser.objects.none()
        if user.is_staff:
            return CustomUser.objects.all()
        return CustomUser.objects.filter(pk=user.pk)


class AttachmentViewSet(viewsets.ModelViewSet):
    queryset = Attachment.objects.all()
    serializer_class = AttachmentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Attachment.objects.filter(uploaded_by=self.request.user)

    def perform_create(self, serializer):
        serializer.save(uploaded_by=self.request.user)


class DigitalWalletViewSet(viewsets.ModelViewSet):
    queryset = DigitalWallet.objects.all()
    serializer_class = DigitalWalletSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return DigitalWallet.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class SpecializedProfessionalViewSet(viewsets.ModelViewSet):
    # Public professional directory: anyone authenticated can read,
    # but only the owner can edit/delete their own profile.
    queryset = SpecializedProfessional.objects.all()
    serializer_class = SpecializedProfessionalSerializer
    permission_classes = [IsAuthenticated, IsOwnerOrReadOnly]

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class ReviewViewSet(viewsets.ModelViewSet):
    # Reviews are publicly readable, but only the author can edit/delete.
    queryset = Review.objects.all()
    serializer_class = ReviewSerializer
    permission_classes = [IsAuthenticated, IsOwnerOrReadOnly]

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class OnboardingProgressViewSet(viewsets.ModelViewSet):
    queryset = OnboardingProgress.objects.all()
    serializer_class = OnboardingProgressSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return OnboardingProgress.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

from django.shortcuts import render
from django.views.generic import TemplateView

class SPAView(TemplateView):
    def get(self, request, path=''):
        # Get the exact path from URL
        template_name = path or 'authentication.html'  # only if empty (like /)

        # DO NOT add .html blindly — user already typed it
        if not template_name.endswith('.html'):
            template_name += '.html'

        # Just render whatever was requested — nothing else
        return render(request, template_name)