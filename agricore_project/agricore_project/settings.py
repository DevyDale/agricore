# ==================== DJANGO SETTINGS (FINAL & PERFECT) ====================
import os
from datetime import timedelta
import environ
from pathlib import Path
import dj_database_url

# ==================== BASE DIR ====================
BASE_DIR = Path(__file__).resolve().parent.parent

# ==================== ENV SETUP ====================
env = environ.Env(
    DEBUG=(bool, True),
)
environ.Env.read_env(os.path.join(BASE_DIR, '.env'))

# ==================== SECURITY & HOSTS ====================
SECRET_KEY = env('SECRET_KEY', default='django-insecure-change-me-in-production')
DEBUG = env.bool('DEBUG', default=True)

ALLOWED_HOSTS = ['127.0.0.1', 'localhost', '0.0.0.0']

# ==================== SECURITY (Safe for local dev) ====================
SECURE_SSL_REDIRECT = False
SESSION_COOKIE_SECURE = False
CSRF_COOKIE_SECURE = False
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_HSTS_SECONDS = 0

# ==================== APPLICATION DEFINITION ====================
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',

    'rest_framework',
    'rest_framework_simplejwt',
    'corsheaders',
    'channels',
    'django_extensions',
    'django_filters',

    'accounts.apps.AccountsConfig',
    'farms.apps.FarmsConfig',
    'crops.apps.CropsConfig',
    'livestock.apps.LivestockConfig',
    'inventory.apps.InventoryConfig',
    'marketplace.apps.MarketplaceConfig',
    'workforce.apps.WorkforceConfig',
    'communications.apps.CommunicationsConfig',
    'ai.apps.AiConfig',
    'analytics.apps.AnalyticsConfig',
    'produce.apps.ProduceConfig',
]

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

# ==================== URLS & ASGI/WSGI ====================
ROOT_URLCONF = 'agricore_project.urls'
WSGI_APPLICATION = 'agricore_project.wsgi.application'
ASGI_APPLICATION = 'agricore_project.asgi.application'

# ==================== TEMPLATES — THIS WAS THE PROBLEM ====================
TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],  # ← THIS LINE WAS MISSING
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

# ==================== DATABASE ====================
DATABASES = {
    'default': dj_database_url.config(
        default=env('DATABASE_URL', default='postgres://postgres:password@localhost:5432/agricore'),
        conn_max_age=600,
        ssl_require=not DEBUG
    )
}

# ==================== PASSWORD VALIDATION ====================
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# ==================== AUTH & JWT ====================
AUTH_USER_MODEL = 'accounts.CustomUser'

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    'DEFAULT_FILTER_BACKENDS': [
        'django_filters.rest_framework.DjangoFilterBackend',
    ],
}

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=60),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=7),
    'AUTH_HEADER_TYPES': ('Bearer',),
}

# ==================== CORS ====================
CORS_ALLOW_ALL_ORIGINS = True
CORS_ALLOW_CREDENTIALS = True

# ==================== CHANNELS + REDIS ====================
REDIS_URL = env('REDIS_URL', default='redis://localhost:6379/0')

CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels_redis.core.RedisChannelLayer',
        'CONFIG': {
            'hosts': [REDIS_URL],
        },
    },
}

# ==================== STATIC & MEDIA ====================
STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
STATICFILES_DIRS = [BASE_DIR / 'static']
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'

# ==================== INTERNATIONALIZATION ====================
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# ==================== KEYS ====================
GROQ_API_KEY = env('GROQ_API_KEY', default='')
SUPABASE_URL = env('SUPABASE_URL', default='')
SUPABASE_ANON_KEY = env('SUPABASE_ANON_KEY', default='')
SUPABASE_SERVICE_ROLE_KEY = env('SUPABASE_SERVICE_ROLE_KEY', default='')