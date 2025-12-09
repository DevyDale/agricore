from rest_framework import viewsets
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
    