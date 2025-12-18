from rest_framework import viewsets
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated, AllowAny
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

    def get(self, request):
        # When called by an authenticated user, return their serialized profile.
        serializer = CustomUserSerializer(request.user)
        return Response(serializer.data)


class GoogleAuthView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        token = request.data.get('token')
        
        if not token:
            return Response(
                {'error': 'Token is required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            # Verify the token with Google
            idinfo = id_token.verify_oauth2_token(
                token,
                requests.Request(),
                '488596909366-vd5s2k861kn6g1v8e8f3u81eig3h2q2c.apps.googleusercontent.com'
            )

            # Get user info from token
            email = idinfo.get('email')
            google_id = idinfo.get('sub')
            name = idinfo.get('name', '')
            
            if not email:
                return Response(
                    {'error': 'Email not provided by Google'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Check if user exists
            user, created = CustomUser.objects.get_or_create(
                email=email,
                defaults={
                    'username': email.split('@')[0] + '_' + google_id[:8],
                    'first_name': name.split()[0] if name else '',
                    'last_name': ' '.join(name.split()[1:]) if len(name.split()) > 1 else '',
                }
            )

            # Generate JWT tokens
            refresh = RefreshToken.for_user(user)
            
            return Response({
                'access': str(refresh.access_token),
                'refresh': str(refresh),
                'user': CustomUserSerializer(user).data
            }, status=status.HTTP_200_OK)

        except ValueError as e:
            return Response(
                {'error': f'Invalid token: {str(e)}'},
                status=status.HTTP_400_BAD_REQUEST
            )
        except Exception as e:
            return Response(
                {'error': f'Authentication failed: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class CustomUserViewSet(viewsets.ModelViewSet):
    queryset = CustomUser.objects.all()
    serializer_class = CustomUserSerializer

    def get_permissions(self):
        if self.action == 'create':
            return [AllowAny()]  # Allow unauthenticated POST
        return [IsAuthenticated()]  # Require auth for other actions


class AttachmentViewSet(viewsets.ModelViewSet):
    queryset = Attachment.objects.all()
    serializer_class = AttachmentSerializer
    permission_classes = [IsAuthenticated]


class DigitalWalletViewSet(viewsets.ModelViewSet):
    queryset = DigitalWallet.objects.all()
    serializer_class = DigitalWalletSerializer
    permission_classes = [IsAuthenticated]


class SpecializedProfessionalViewSet(viewsets.ModelViewSet):
    queryset = SpecializedProfessional.objects.all()
    serializer_class = SpecializedProfessionalSerializer
    permission_classes = [IsAuthenticated]


class ReviewViewSet(viewsets.ModelViewSet):
    queryset = Review.objects.all()
    serializer_class = ReviewSerializer
    permission_classes = [IsAuthenticated]


class OnboardingProgressViewSet(viewsets.ModelViewSet):
    queryset = OnboardingProgress.objects.all()
    serializer_class = OnboardingProgressSerializer
    permission_classes = [IsAuthenticated]

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