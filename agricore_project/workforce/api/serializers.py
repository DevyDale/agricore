from rest_framework import serializers
from workforce.models import (
    Employee, Machinery, Equipment, EmployeePerformance, FiredEmployee,
    ProfessionalProfile, ProfessionalReview, JobPosting, JobApplication
)
from django.contrib.auth import get_user_model
import re

User = get_user_model()


# Professional Profile Serializers
class ProfessionalProfileListSerializer(serializers.ModelSerializer):
    """Lightweight serializer for listing professionals"""
    user_name = serializers.CharField(source='user.get_full_name', read_only=True)
    user_email = serializers.EmailField(source='user.email', read_only=True)
    specialty_display = serializers.CharField(source='get_specialty_display', read_only=True)
    availability_display = serializers.CharField(source='get_availability_display', read_only=True)
    profile_image_url = serializers.SerializerMethodField()
    
    class Meta:
        model = ProfessionalProfile
        fields = [
            'id', 'user_name', 'user_email', 'profile_image_url', 'location',
            'specialty', 'specialty_display', 'years_experience', 'hourly_rate',
            'availability', 'availability_display', 'average_rating', 'total_reviews',
            'is_verified', 'featured', 'bio', 'response_time', 'total_jobs_completed'
        ]
    
    def get_profile_image_url(self, obj):
        if obj.profile_image:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.profile_image.url)
        return None


class ProfessionalReviewSerializer(serializers.ModelSerializer):
    reviewer_name = serializers.CharField(source='reviewer.get_full_name', read_only=True)
    reviewer_username = serializers.CharField(source='reviewer.username', read_only=True)
    
    class Meta:
        model = ProfessionalReview
        fields = [
            'id', 'professional', 'reviewer', 'reviewer_name', 'reviewer_username',
            'rating', 'title', 'comment', 'job_title', 'work_quality',
            'professionalism', 'communication', 'timeliness', 'is_verified',
            'helpful_count', 'response', 'response_date', 'created_at', 'updated_at'
        ]
        read_only_fields = ['reviewer', 'helpful_count', 'created_at', 'updated_at']
    
    def validate_rating(self, value):
        if value < 1 or value > 5:
            raise serializers.ValidationError("Rating must be between 1 and 5")
        return value
    
    def create(self, validated_data):
        validated_data['reviewer'] = self.context['request'].user
        review = super().create(validated_data)
        # Update professional's average rating
        review.professional.update_rating()
        return review


class ProfessionalProfileDetailSerializer(serializers.ModelSerializer):
    """Detailed serializer for individual professional view"""
    user_name = serializers.CharField(source='user.get_full_name', read_only=True)
    user_email = serializers.EmailField(source='user.email', read_only=True)
    user_username = serializers.CharField(source='user.username', read_only=True)
    specialty_display = serializers.CharField(source='get_specialty_display', read_only=True)
    availability_display = serializers.CharField(source='get_availability_display', read_only=True)
    profile_image_url = serializers.SerializerMethodField()
    resume_url = serializers.SerializerMethodField()
    reviews = ProfessionalReviewSerializer(many=True, read_only=True)
    
    class Meta:
        model = ProfessionalProfile
        fields = '__all__'
        read_only_fields = [
            'user', 'average_rating', 'total_reviews', 'total_jobs_completed',
            'created_at', 'updated_at'
        ]
    
    def get_profile_image_url(self, obj):
        if obj.profile_image:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.profile_image.url)
        return None
    
    def get_resume_url(self, obj):
        if obj.resume:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.resume.url)
        return None


class ProfessionalProfileCreateUpdateSerializer(serializers.ModelSerializer):
    """Serializer for creating/updating professional profiles"""
    
    class Meta:
        model = ProfessionalProfile
        fields = [
            'profile_image', 'bio', 'phone', 'location', 'specialty',
            'years_experience', 'hourly_rate', 'availability', 'education',
            'work_experience', 'skills', 'certifications', 'languages',
            'notable_projects', 'linkedin_url', 'portfolio_url', 'resume',
            'response_time'
        ]
    
    def validate_years_experience(self, value):
        if value < 0:
            raise serializers.ValidationError("Years of experience cannot be negative")
        return value
    
    def validate_hourly_rate(self, value):
        if value < 0:
            raise serializers.ValidationError("Hourly rate cannot be negative")
        return value
    
    def validate_skills(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Skills must be a list")
        return value
    
    def validate_certifications(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Certifications must be a list")
        return value


# Job Posting Serializers
class JobPostingSerializer(serializers.ModelSerializer):
    employer_name = serializers.CharField(source='employer.get_full_name', read_only=True)
    farm_name = serializers.CharField(source='farm.name', read_only=True)
    specialty_display = serializers.CharField(source='get_specialty_required_display', read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    applications_count = serializers.IntegerField(source='applications.count', read_only=True)
    
    class Meta:
        model = JobPosting
        fields = '__all__'
        read_only_fields = ['employer', 'created_at', 'updated_at']
    
    def create(self, validated_data):
        validated_data['employer'] = self.context['request'].user
        return super().create(validated_data)


class JobApplicationSerializer(serializers.ModelSerializer):
    professional_name = serializers.CharField(source='professional.user.get_full_name', read_only=True)
    professional_rating = serializers.DecimalField(
        source='professional.average_rating',
        max_digits=3,
        decimal_places=2,
        read_only=True
    )
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    
    class Meta:
        model = JobApplication
        fields = '__all__'
        read_only_fields = ['professional', 'status', 'applied_at', 'updated_at']
    
    def create(self, validated_data):
        user = self.context['request'].user
        try:
            professional_profile = user.professional_profile
            validated_data['professional'] = professional_profile
        except ProfessionalProfile.DoesNotExist:
            raise serializers.ValidationError("You must have a professional profile to apply for jobs")
        return super().create(validated_data)


# Original Employee Serializers (keep for backward compatibility)
class EmployeeSerializer(serializers.ModelSerializer):
    class Meta:
        model = Employee
        fields = ['id', 'first_name', 'last_name', 'phone', 'country_code', 'role',
                  'employment_type', 'hire_date', 'salary', 'additional_notes']

    def validate_phone(self, value):
        if value and not re.match(r'^\+?\d{7,15}$', value):
            raise serializers.ValidationError("Enter a valid phone number with optional '+' and 7-15 digits.")
        return value

    def validate_salary(self, value):
        if value < 0:
            raise serializers.ValidationError("Salary must be non-negative.")
        return value

class MachinerySerializer(serializers.ModelSerializer):
    class Meta:
        model = Machinery
        fields = '__all__'

class EquipmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Equipment
        fields = '__all__'

class EmployeePerformanceSerializer(serializers.ModelSerializer):
    class Meta:
        model = EmployeePerformance
        fields = '__all__'

class FiredEmployeeSerializer(serializers.ModelSerializer):
    class Meta:
        model = FiredEmployee
        fields = '__all__'