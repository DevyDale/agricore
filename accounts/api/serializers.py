from rest_framework import serializers
from accounts.models import CustomUser, Attachment, DigitalWallet, SpecializedProfessional, Review, OnboardingProgress

class CustomUserSerializer(serializers.ModelSerializer):
    class Meta:
        model = CustomUser
        fields = ['id', 'username', 'email', 'password', 'phone', 'country_code', 'is_verified', 'created_at', 'last_login']
        extra_kwargs = {
            'password': {'write_only': True, 'required': True},
            'last_login': {'read_only': True}
        }

    def create(self, validated_data):
        # Extract password and remove it from validated_data
        password = validated_data.pop('password')
        # Create user with required fields
        user = CustomUser.objects.create_user(
            username=validated_data['username'],
            email=validated_data['email'],
            password=password
        )
        # Set additional fields
        user.phone = validated_data.get('phone', '')
        user.country_code = validated_data.get('country_code', '')
        user.save()
        return user

class AttachmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Attachment
        fields = '__all__'

class DigitalWalletSerializer(serializers.ModelSerializer):
    class Meta:
        model = DigitalWallet
        fields = '__all__'

class SpecializedProfessionalSerializer(serializers.ModelSerializer):
    class Meta:
        model = SpecializedProfessional
        fields = '__all__'

class ReviewSerializer(serializers.ModelSerializer):
    class Meta:
        model = Review
        fields = '__all__'

class OnboardingProgressSerializer(serializers.ModelSerializer):
    class Meta:
        model = OnboardingProgress
        fields = '__all__'