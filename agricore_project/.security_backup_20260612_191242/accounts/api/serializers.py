from rest_framework import serializers
from accounts.models import CustomUser, Attachment, DigitalWallet, SpecializedProfessional, Review, OnboardingProgress
class CustomUserSerializer(serializers.ModelSerializer):
    class Meta:
        model = CustomUser
        fields = ['id', 'username', 'email', 'password', 'phone', 'country_code', 
                  'is_verified', 'created_at', 'last_login', 'role']
        extra_kwargs = {
            'password': {'write_only': True},
            'last_login': {'read_only': True},
            'role': {'required': False, 'allow_null': True}  # ← THIS LINE WAS MISSING
        }

    def create(self, validated_data):
        password = validated_data.pop('password')
        user = CustomUser.objects.create_user(
            username=validated_data['username'],
            email=validated_data['email'],
            password=password
        )
        user.phone = validated_data.get('phone', '')
        user.country_code = validated_data.get('country_code', '')
        user.role = validated_data.get('role')  # ← Allow role on create
        user.save()
        return user

    def update(self, instance, validated_data):
        # ← ADD THIS METHOD TO ALLOW UPDATING ROLE
        instance.role = validated_data.get('role', instance.role)
        instance.save()
        return instance
class AttachmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Attachment
        fields = '__all__'

class DigitalWalletSerializer(serializers.ModelSerializer):
    class Meta:
        model = DigitalWallet
        fields = '__all__'

class SpecializedProfessionalSerializer(serializers.ModelSerializer):
    profile_image_display = serializers.SerializerMethodField(read_only=True)
    
    class Meta:
        model = SpecializedProfessional
        fields = '__all__'
    
    def get_profile_image_display(self, obj):
        """Return absolute URL for profile image (from file or URL field)"""
        request = self.context.get('request')
        if obj.profile_image:
            if request:
                return request.build_absolute_uri(obj.profile_image.url)
            return obj.profile_image.url
        elif obj.profile_image_url:
            return obj.profile_image_url
        return None

class ReviewSerializer(serializers.ModelSerializer):
    class Meta:
        model = Review
        fields = '__all__'

class OnboardingProgressSerializer(serializers.ModelSerializer):
    class Meta:
        model = OnboardingProgress
        fields = '__all__'