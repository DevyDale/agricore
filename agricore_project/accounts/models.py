from django.contrib.auth.models import AbstractUser
from django.db import models
from django.core.validators import RegexValidator

class CustomUser(AbstractUser):
    username = models.CharField(
        max_length=150,
        unique=True,
        validators=[RegexValidator(r'^\S+$', 'Username cannot contain spaces.')]
    )
    email = models.EmailField(unique=True)
    phone = models.CharField(max_length=32, blank=True, null=True)
    country_code = models.CharField(max_length=8, blank=True, null=True)
    is_verified = models.BooleanField(default=False)

    # THIS IS THE NEW FIELD
    ROLE_CHOICES = [
        ('farmer', 'Farmer'),
        ('retailer', 'Retailer / Buyer'),
        ('specialized', 'Specialized Professional'),
    ]
    role = models.CharField(max_length=20, choices=ROLE_CHOICES, blank=True, null=True)

    created_at = models.DateTimeField(auto_now_add=True)
    last_login = models.DateTimeField(blank=True, null=True)

    def __str__(self):
        return self.username

class Attachment(models.Model):
    owner_type = models.CharField(max_length=50)
    owner_id = models.IntegerField()
    filename = models.CharField(max_length=255)
    url = models.URLField()
    uploaded_by = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    uploaded_at = models.DateTimeField(auto_now_add=True)

class DigitalWallet(models.Model):
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    balance = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    currency = models.CharField(max_length=3, default='USD')
    bank_cards = models.JSONField(default=dict, blank=True)
    coupons = models.JSONField(default=list, blank=True)
    last_transaction = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

class SpecializedProfessional(models.Model):
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    profession = models.CharField(max_length=50)
    bio = models.TextField(blank=True)
    contact_phone = models.CharField(max_length=32, blank=True)
    country_code = models.CharField(max_length=8, blank=True)
    rating = models.DecimalField(max_digits=3, decimal_places=2, default=0)
    # Profile image: supports both file upload and URL
    profile_image = models.ImageField(upload_to='professional_profiles/', blank=True, null=True)
    profile_image_url = models.URLField(blank=True, null=True, help_text='Alternative to uploading: provide image URL')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class Review(models.Model):
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    workforce = models.ForeignKey(SpecializedProfessional, on_delete=models.CASCADE)
    rating = models.IntegerField()
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

class OnboardingProgress(models.Model):
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    step = models.CharField(max_length=50)
    status = models.CharField(max_length=20, default='pending')
    completed_at = models.DateTimeField(blank=True, null=True)