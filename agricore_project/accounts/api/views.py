from rest_framework import viewsets
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated, AllowAny
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