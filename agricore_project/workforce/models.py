from django.db import models
from django.contrib.auth import get_user_model
from django.core.validators import MinValueValidator, MaxValueValidator
from farms.models import Farm

User = get_user_model()

# Professional Profile Model
class ProfessionalProfile(models.Model):
    SPECIALTY_CHOICES = [
        ('agronomist', 'Agronomist'),
        ('veterinarian', 'Veterinarian'),
        ('mechanic', 'Mechanic'),
        ('chemist', 'Chemist'),
        ('farm_manager', 'Farm Manager'),
        ('agricultural_engineer', 'Agricultural Engineer'),
        ('soil_scientist', 'Soil Scientist'),
        ('crop_consultant', 'Crop Consultant'),
        ('pest_control', 'Pest Control Specialist'),
        ('livestock_handler', 'Livestock Handler'),
        ('irrigation_specialist', 'Irrigation Specialist'),
        ('agricultural_economist', 'Agricultural Economist'),
        ('horticulturist', 'Horticulturist'),
        ('agricultural_technician', 'Agricultural Technician'),
        ('food_safety', 'Food Safety Specialist'),
        ('data_analyst', 'Agricultural Data Analyst'),
        ('farm_laborer', 'Farm Laborer'),
        ('equipment_operator', 'Equipment Operator'),
        ('harvester', 'Harvester'),
        ('planting_specialist', 'Planting Specialist'),
    ]
    
    AVAILABILITY_CHOICES = [
        ('full_time', 'Full-Time'),
        ('part_time', 'Part-Time'),
        ('contract', 'Contract'),
        ('seasonal', 'Seasonal'),
        ('available', 'Available Now'),
        ('not_available', 'Not Available'),
    ]

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='professional_profile')
    
    # Basic Information
    profile_image = models.ImageField(upload_to='professional_profiles/', blank=True, null=True)
    bio = models.TextField(max_length=500, blank=True)
    phone = models.CharField(max_length=20, blank=True)
    location = models.CharField(max_length=200)
    specialty = models.CharField(max_length=50, choices=SPECIALTY_CHOICES)
    
    # Professional Details
    years_experience = models.IntegerField(validators=[MinValueValidator(0)])
    hourly_rate = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(0)])
    availability = models.CharField(max_length=20, choices=AVAILABILITY_CHOICES, default='available')
    
    # Detailed Information
    education = models.TextField(blank=True, help_text="Educational background")
    work_experience = models.TextField(blank=True, help_text="Detailed work experience")
    skills = models.JSONField(default=list, help_text="List of skills")
    certifications = models.JSONField(default=list, help_text="List of certifications")
    languages = models.JSONField(default=list, help_text="Languages spoken")
    
    # Portfolio
    notable_projects = models.TextField(blank=True)
    linkedin_url = models.URLField(blank=True)
    portfolio_url = models.URLField(blank=True)
    resume = models.FileField(upload_to='resumes/', blank=True, null=True)
    
    # Statistics
    total_jobs_completed = models.IntegerField(default=0)
    average_rating = models.DecimalField(max_digits=3, decimal_places=2, default=0.00)
    total_reviews = models.IntegerField(default=0)
    response_time = models.CharField(max_length=50, default="Within 24 hours")
    
    # Status
    is_verified = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    featured = models.BooleanField(default=False)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.user.get_full_name() or self.user.username} - {self.get_specialty_display()}"

    class Meta:
        ordering = ['-featured', '-average_rating', '-created_at']
        indexes = [
            models.Index(fields=['specialty', 'location']),
            models.Index(fields=['availability', 'is_active']),
        ]

    def update_rating(self):
        """Update average rating based on reviews"""
        reviews = self.reviews.all()
        if reviews.exists():
            self.average_rating = reviews.aggregate(models.Avg('rating'))['rating__avg']
            self.total_reviews = reviews.count()
            self.save(update_fields=['average_rating', 'total_reviews'])


# Professional Review Model
class ProfessionalReview(models.Model):
    professional = models.ForeignKey(ProfessionalProfile, on_delete=models.CASCADE, related_name='reviews')
    reviewer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='given_reviews')
    
    # Review Details
    rating = models.IntegerField(validators=[MinValueValidator(1), MaxValueValidator(5)])
    title = models.CharField(max_length=200)
    comment = models.TextField()
    
    # Job Context
    job_title = models.CharField(max_length=200, blank=True)
    work_quality = models.IntegerField(validators=[MinValueValidator(1), MaxValueValidator(5)], null=True, blank=True)
    professionalism = models.IntegerField(validators=[MinValueValidator(1), MaxValueValidator(5)], null=True, blank=True)
    communication = models.IntegerField(validators=[MinValueValidator(1), MaxValueValidator(5)], null=True, blank=True)
    timeliness = models.IntegerField(validators=[MinValueValidator(1), MaxValueValidator(5)], null=True, blank=True)
    
    # Status
    is_verified = models.BooleanField(default=False, help_text="Verified purchase/hire")
    helpful_count = models.IntegerField(default=0)
    
    # Response
    response = models.TextField(blank=True, help_text="Professional's response to review")
    response_date = models.DateTimeField(null=True, blank=True)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Review for {self.professional} by {self.reviewer.username} - {self.rating}★"

    class Meta:
        ordering = ['-created_at']
        unique_together = ['professional', 'reviewer']  # One review per user per professional


# Job Posting Model
class JobPosting(models.Model):
    STATUS_CHOICES = [
        ('open', 'Open'),
        ('in_progress', 'In Progress'),
        ('completed', 'Completed'),
        ('cancelled', 'Cancelled'),
    ]

    employer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='job_postings')
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='job_postings', null=True, blank=True)
    
    # Job Details
    title = models.CharField(max_length=200)
    description = models.TextField()
    specialty_required = models.CharField(max_length=50, choices=ProfessionalProfile.SPECIALTY_CHOICES)
    location = models.CharField(max_length=200)
    
    # Compensation
    budget = models.DecimalField(max_digits=10, decimal_places=2)
    payment_type = models.CharField(max_length=20, choices=[
        ('hourly', 'Hourly'),
        ('fixed', 'Fixed Price'),
        ('daily', 'Daily Rate'),
    ])
    
    # Timeline
    start_date = models.DateField()
    end_date = models.DateField(null=True, blank=True)
    duration = models.CharField(max_length=100, blank=True)
    
    # Requirements
    experience_required = models.IntegerField(default=0)
    skills_required = models.JSONField(default=list)
    
    # Status
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='open')
    hired_professional = models.ForeignKey(ProfessionalProfile, on_delete=models.SET_NULL, null=True, blank=True, related_name='hired_jobs')
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.title} - {self.get_status_display()}"

    class Meta:
        ordering = ['-created_at']


# Job Application Model
class JobApplication(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('accepted', 'Accepted'),
        ('rejected', 'Rejected'),
        ('withdrawn', 'Withdrawn'),
    ]

    job = models.ForeignKey(JobPosting, on_delete=models.CASCADE, related_name='applications')
    professional = models.ForeignKey(ProfessionalProfile, on_delete=models.CASCADE, related_name='job_applications')
    
    # Application Details
    cover_letter = models.TextField()
    proposed_rate = models.DecimalField(max_digits=10, decimal_places=2)
    availability_start = models.DateField()
    
    # Status
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    
    # Timestamps
    applied_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.professional} applied for {self.job.title}"

    class Meta:
        ordering = ['-applied_at']
        unique_together = ['job', 'professional']


# Original Employee Model (keep for backward compatibility)
class Employee(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='employees')
    first_name = models.CharField(max_length=100)
    last_name = models.CharField(max_length=100)
    phone = models.CharField(max_length=15)
    country_code = models.CharField(max_length=5)
    role = models.CharField(max_length=50)
    employment_type = models.CharField(max_length=50)
    hire_date = models.DateField()
    salary = models.DecimalField(max_digits=10, decimal_places=2)
    additional_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.first_name} {self.last_name} ({self.role})"

    class Meta:
        ordering = ['first_name', 'last_name']

class Machinery(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    name = models.CharField(max_length=255)
    type = models.CharField(max_length=50)
    description = models.TextField(blank=True)
    assigned_to = models.ForeignKey(Employee, related_name='assigned_machinery', on_delete=models.SET_NULL, null=True, blank=True)
    purchased_by = models.ForeignKey(Employee, related_name='purchased_machinery', on_delete=models.SET_NULL, null=True, blank=True)
    purchased_on = models.DateField(blank=True, null=True)
    value = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=50)
    created_at = models.DateTimeField(auto_now_add=True)

class Equipment(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE)
    name = models.CharField(max_length=255)
    type = models.CharField(max_length=50)
    description = models.TextField(blank=True)
    assigned_to = models.ForeignKey(Employee, related_name='assigned_equipment', on_delete=models.SET_NULL, null=True, blank=True)
    purchased_by = models.ForeignKey(Employee, related_name='purchased_equipment', on_delete=models.SET_NULL, null=True, blank=True)
    purchased_on = models.DateField(blank=True, null=True)
    value = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=50)
    created_at = models.DateTimeField(auto_now_add=True)

class EmployeePerformance(models.Model):
    employee = models.ForeignKey(Employee, on_delete=models.CASCADE, related_name='performance_records')
    skillset = models.CharField(max_length=100)
    performance_rating = models.CharField(max_length=50)
    review_notes = models.TextField(blank=True)
    reviewed_at = models.DateTimeField()
    ai_recommendation = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['reviewed_at']

class FiredEmployee(models.Model):
    employee_id = models.IntegerField()
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='fired_employees')
    reason = models.TextField()
    fired_at = models.DateTimeField()
    rehired = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['fired_at']