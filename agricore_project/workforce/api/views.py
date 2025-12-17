from rest_framework import viewsets, status, filters
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework import serializers
from django_filters.rest_framework import DjangoFilterBackend
from django.db.models import Q, Avg

from workforce.models import (
    Employee, Machinery, Equipment, EmployeePerformance, FiredEmployee,
    ProfessionalProfile, ProfessionalReview, JobPosting, JobApplication
)
from .serializers import (
    EmployeeSerializer, MachinerySerializer, EquipmentSerializer,
    EmployeePerformanceSerializer, FiredEmployeeSerializer,
    ProfessionalProfileListSerializer, ProfessionalProfileDetailSerializer,
    ProfessionalProfileCreateUpdateSerializer, ProfessionalReviewSerializer,
    JobPostingSerializer, JobApplicationSerializer
)


class ProfessionalProfileViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing professional profiles in the agricultural network.
    Supports searching, filtering, and rating.
    """
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    filterset_fields = ['specialty', 'availability', 'is_verified', 'location']
    search_fields = ['user__first_name', 'user__last_name', 'bio', 'skills', 'location']
    ordering_fields = ['average_rating', 'hourly_rate', 'years_experience', 'created_at']
    ordering = ['-featured', '-average_rating']

    # All actions require authentication

    def get_queryset(self):
        queryset = ProfessionalProfile.objects.filter(is_active=True).select_related('user')
        
        # Filter by minimum rating
        min_rating = self.request.query_params.get('min_rating')
        if min_rating:
            try:
                queryset = queryset.filter(average_rating__gte=float(min_rating))
            except ValueError:
                pass
        
        # Filter by max hourly rate
        max_rate = self.request.query_params.get('max_rate')
        if max_rate:
            try:
                queryset = queryset.filter(hourly_rate__lte=float(max_rate))
            except ValueError:
                pass
        
        # Filter by minimum experience
        min_experience = self.request.query_params.get('min_experience')
        if min_experience:
            try:
                queryset = queryset.filter(years_experience__gte=int(min_experience))
            except ValueError:
                pass
        
        # Search by skills
        skills = self.request.query_params.get('skills')
        if skills:
            skill_list = [s.strip() for s in skills.split(',')]
            for skill in skill_list:
                queryset = queryset.filter(skills__icontains=skill)
        
        return queryset

    def get_serializer_class(self):
        if self.action == 'list':
            return ProfessionalProfileListSerializer
        elif self.action in ['create', 'update', 'partial_update']:
            return ProfessionalProfileCreateUpdateSerializer
        return ProfessionalProfileDetailSerializer

    def perform_create(self, serializer):
        """Create profile for current user"""
        serializer.save(user=self.request.user)

    @action(detail=False, methods=['get'])
    def me(self, request):
        """Get current user's professional profile"""
        try:
            profile = request.user.professional_profile
            serializer = ProfessionalProfileDetailSerializer(profile, context={'request': request})
            return Response(serializer.data)
        except ProfessionalProfile.DoesNotExist:
            return Response(
                {'detail': 'Professional profile not found. Create one to join the network.'},
                status=status.HTTP_404_NOT_FOUND
            )

    @action(detail=False, methods=['post', 'put', 'patch'])
    def update_me(self, request):
        """Create or update current user's professional profile"""
        try:
            profile = request.user.professional_profile
            serializer = ProfessionalProfileCreateUpdateSerializer(
                profile,
                data=request.data,
                partial=request.method == 'PATCH',
                context={'request': request}
            )
        except ProfessionalProfile.DoesNotExist:
            serializer = ProfessionalProfileCreateUpdateSerializer(
                data=request.data,
                context={'request': request}
            )
        
        serializer.is_valid(raise_exception=True)
        serializer.save(user=request.user)
        
        # Return full profile data
        profile = request.user.professional_profile
        response_serializer = ProfessionalProfileDetailSerializer(profile, context={'request': request})
        return Response(response_serializer.data)

    @action(detail=True, methods=['post'])
    def toggle_featured(self, request, pk=None):
        """Admin action to toggle featured status"""
        if not request.user.is_staff:
            return Response(
                {'detail': 'Only admins can feature professionals'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        profile = self.get_object()
        profile.featured = not profile.featured
        profile.save()
        serializer = self.get_serializer(profile)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def verify(self, request, pk=None):
        """Admin action to verify a professional"""
        if not request.user.is_staff:
            return Response(
                {'detail': 'Only admins can verify professionals'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        profile = self.get_object()
        profile.is_verified = True
        profile.save()
        serializer = self.get_serializer(profile)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def featured(self, request):
        """Get featured professionals"""
        featured_profiles = self.get_queryset().filter(featured=True)[:10]
        serializer = ProfessionalProfileListSerializer(
            featured_profiles,
            many=True,
            context={'request': request}
        )
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def top_rated(self, request):
        """Get top rated professionals"""
        top_profiles = self.get_queryset().filter(total_reviews__gte=3).order_by('-average_rating')[:10]
        serializer = ProfessionalProfileListSerializer(
            top_profiles,
            many=True,
            context={'request': request}
        )
        return Response(serializer.data)


class ProfessionalReviewViewSet(viewsets.ModelViewSet):
    """ViewSet for managing professional reviews"""
    serializer_class = ProfessionalReviewSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [filters.OrderingFilter]
    ordering_fields = ['created_at', 'rating', 'helpful_count']
    ordering = ['-created_at']

    # All actions require authentication

    def get_queryset(self):
        queryset = ProfessionalReview.objects.all().select_related('professional', 'reviewer')
        
        # Filter by professional
        professional_id = self.request.query_params.get('professional')
        if professional_id:
            queryset = queryset.filter(professional_id=professional_id)
        
        # Filter by minimum rating
        min_rating = self.request.query_params.get('min_rating')
        if min_rating:
            try:
                queryset = queryset.filter(rating__gte=int(min_rating))
            except ValueError:
                pass
        
        return queryset

    def perform_create(self, serializer):
        """Create review and update professional's rating"""
        serializer.save(reviewer=self.request.user)

    @action(detail=True, methods=['post'])
    def mark_helpful(self, request, pk=None):
        """Mark a review as helpful"""
        review = self.get_object()
        review.helpful_count += 1
        review.save()
        serializer = self.get_serializer(review)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def respond(self, request, pk=None):
        """Professional responds to a review"""
        review = self.get_object()
        
        # Check if user is the professional being reviewed
        if review.professional.user != request.user:
            return Response(
                {'detail': 'Only the reviewed professional can respond'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        response_text = request.data.get('response')
        if not response_text:
            return Response(
                {'detail': 'Response text is required'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        review.response = response_text
        from django.utils import timezone
        review.response_date = timezone.now()
        review.save()
        
        serializer = self.get_serializer(review)
        return Response(serializer.data)


class JobPostingViewSet(viewsets.ModelViewSet):
    """ViewSet for managing job postings"""
    serializer_class = JobPostingSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    filterset_fields = ['status', 'specialty_required', 'payment_type']
    search_fields = ['title', 'description', 'location']
    ordering_fields = ['created_at', 'start_date', 'budget']
    ordering = ['-created_at']

    def get_queryset(self):
        queryset = JobPosting.objects.all().select_related('employer', 'farm')
        
        # Filter jobs by user's specialty if they're a professional
        if hasattr(self.request.user, 'professional_profile'):
            specialty = self.request.query_params.get('my_specialty')
            if specialty == 'true':
                queryset = queryset.filter(
                    specialty_required=self.request.user.professional_profile.specialty
                )
        
        return queryset

    @action(detail=False, methods=['get'])
    def my_postings(self, request):
        """Get current user's job postings"""
        postings = self.get_queryset().filter(employer=request.user)
        serializer = self.get_serializer(postings, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def hire(self, request, pk=None):
        """Hire a professional for this job"""
        job = self.get_object()
        
        if job.employer != request.user:
            return Response(
                {'detail': 'Only the job poster can hire for this position'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        application_id = request.data.get('application_id')
        if not application_id:
            return Response(
                {'detail': 'application_id is required'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            application = job.applications.get(id=application_id)
            job.hired_professional = application.professional
            job.status = 'in_progress'
            job.save()
            
            application.status = 'accepted'
            application.save()
            
            # Reject other applications
            job.applications.exclude(id=application_id).update(status='rejected')
            
            serializer = self.get_serializer(job)
            return Response(serializer.data)
        except JobApplication.DoesNotExist:
            return Response(
                {'detail': 'Application not found'},
                status=status.HTTP_404_NOT_FOUND
            )


class JobApplicationViewSet(viewsets.ModelViewSet):
    """ViewSet for managing job applications"""
    serializer_class = JobApplicationSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [filters.OrderingFilter]
    ordering_fields = ['applied_at', 'proposed_rate']
    ordering = ['-applied_at']

    def get_queryset(self):
        user = self.request.user
        
        # If user is a professional, show their applications
        if hasattr(user, 'professional_profile'):
            return JobApplication.objects.filter(
                professional=user.professional_profile
            ).select_related('job', 'professional')
        
        # If user is an employer, show applications to their jobs
        return JobApplication.objects.filter(
            job__employer=user
        ).select_related('job', 'professional')

    @action(detail=False, methods=['get'])
    def my_applications(self, request):
        """Get current professional's applications"""
        if not hasattr(request.user, 'professional_profile'):
            return Response(
                {'detail': 'You must have a professional profile to view applications'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        applications = JobApplication.objects.filter(
            professional=request.user.professional_profile
        )
        serializer = self.get_serializer(applications, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def withdraw(self, request, pk=None):
        """Withdraw a job application"""
        application = self.get_object()
        
        if application.professional.user != request.user:
            return Response(
                {'detail': 'You can only withdraw your own applications'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        if application.status != 'pending':
            return Response(
                {'detail': 'Can only withdraw pending applications'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        application.status = 'withdrawn'
        application.save()
        serializer = self.get_serializer(application)
        return Response(serializer.data)


# Original ViewSets (keep for backward compatibility)
class EmployeeViewSet(viewsets.ModelViewSet):
    serializer_class = EmployeeSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Employee.objects.filter(farm__owner=self.request.user)

    def perform_create(self, serializer):
        farm = getattr(self.request.user, 'farm', None)
        if not farm:
            raise serializers.ValidationError("Current user has no associated farm.")
        serializer.save(farm=farm)

class MachineryViewSet(viewsets.ModelViewSet):
    queryset = Machinery.objects.all()
    serializer_class = MachinerySerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)

class EquipmentViewSet(viewsets.ModelViewSet):
    queryset = Equipment.objects.all()
    serializer_class = EquipmentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)

class EmployeePerformanceViewSet(viewsets.ModelViewSet):
    queryset = EmployeePerformance.objects.all()
    serializer_class = EmployeePerformanceSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(employee__farm__owner=self.request.user)

class FiredEmployeeViewSet(viewsets.ModelViewSet):
    queryset = FiredEmployee.objects.all()
    serializer_class = FiredEmployeeSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)