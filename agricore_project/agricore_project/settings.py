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

ALLOWED_HOSTS = env.list(
    'ALLOWED_HOSTS',
    default=['127.0.0.1', 'localhost', '0.0.0.0', '10.0.2.2', '.ngrok-free.dev', '.ngrok-free.app'],
)

# ==================== SECURITY ====================
# Relaxed in DEBUG (local dev), hardened automatically when DEBUG is off (prod).
SECURE_SSL_REDIRECT = env.bool('SECURE_SSL_REDIRECT', default=not DEBUG)
SESSION_COOKIE_SECURE = env.bool('SESSION_COOKIE_SECURE', default=not DEBUG)
CSRF_COOKIE_SECURE = env.bool('CSRF_COOKIE_SECURE', default=not DEBUG)
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_HSTS_SECONDS = env.int('SECURE_HSTS_SECONDS', default=0 if DEBUG else 31536000)
SECURE_HSTS_INCLUDE_SUBDOMAINS = not DEBUG
SECURE_HSTS_PRELOAD = not DEBUG

# ==================== APPLICATION DEFINITION ====================
INSTALLED_APPS = [
    # African Agricultural Commerce Ecosystem - Phase 1
    'marketprices.apps.MarketPricesConfig',
    'logistics.apps.LogisticsConfig',
    'escrow.apps.EscrowConfig',
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',

    'rest_framework',
    'drf_spectacular',
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
    'utils.apps.UtilsConfig',
    'expenses.apps.ExpensesConfig',
    'notifications.apps.NotificationsConfig',
    'weather.apps.WeatherConfig',
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
        conn_max_age=0,  # Reduce idle connection time to help avoid max clients error
        ssl_require=not DEBUG
    )
}

# If you keep hitting max clients, try lowering CONN_MAX_AGE further (e.g., 10),
# and ensure you are not running multiple servers or scripts at once.

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
    # Rate limiting: blunt brute-force / scraping / abuse of the API, including
    # the unauthenticated login and app-less rider-link endpoints. The payment
    # webhook opts out (see FlutterwaveWebhookView) so provider callbacks are
    # never dropped.
    'DEFAULT_THROTTLE_CLASSES': [
        'rest_framework.throttling.UserRateThrottle',
        'rest_framework.throttling.AnonRateThrottle',
    ],
    'DEFAULT_THROTTLE_RATES': {
        'user': '2000/hour',
        'anon': '60/hour',
    },
}

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=60),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=7),
    'AUTH_HEADER_TYPES': ('Bearer',),
}

# ==================== CORS ====================
# Never combine ALLOW_ALL_ORIGINS with ALLOW_CREDENTIALS in production.
CORS_ALLOW_ALL_ORIGINS = env.bool('CORS_ALLOW_ALL_ORIGINS', default=DEBUG)
CORS_ALLOWED_ORIGINS = env.list('CORS_ALLOWED_ORIGINS', default=[])
CORS_ALLOW_CREDENTIALS = env.bool('CORS_ALLOW_CREDENTIALS', default=True)

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
OLLAMA_MODEL = env('OLLAMA_MODEL', default='mistral')
OLLAMA_BASE_URL = env('OLLAMA_BASE_URL', default='http://localhost:11434/v1/chat/completions')

# ==================== CEREBRAS (Dale AI) ====================
CEREBRAS_API_KEY = env('CEREBRAS_API_KEY', default='')
CEREBRAS_MODEL = env('CEREBRAS_MODEL', default='gpt-oss-120b')
GEMINI_API_KEY = env('GEMINI_API_KEY', default='')
GEMINI_MODEL = env('GEMINI_MODEL', default='gemini-2.0-flash')
SUPABASE_URL = env('SUPABASE_URL', default='')
SUPABASE_ANON_KEY = env('SUPABASE_ANON_KEY', default='')
SUPABASE_SERVICE_ROLE_KEY = env('SUPABASE_SERVICE_ROLE_KEY', default='')
# ==================== CLOUDINARY ====================
CLOUDINARY_CLOUD_NAME = env('CLOUDINARY_CLOUD_NAME', default='')
CLOUDINARY_API_KEY = env('CLOUDINARY_API_KEY', default='')
CLOUDINARY_API_SECRET = env('CLOUDINARY_API_SECRET', default='')

# ==================== FLUTTERWAVE (Payments) ====================
FLW_PUBLIC_KEY = env('FLW_PUBLIC_KEY', default='')
FLW_SECRET_KEY = env('FLW_SECRET_KEY', default='')
FLW_SECRET_HASH = env('FLW_SECRET_HASH', default='')  # same value as the Flutterwave dashboard webhook hash
DEFAULT_CURRENCY = env('DEFAULT_CURRENCY', default='UGX')
PLATFORM_FEE_PERCENT = env.float('PLATFORM_FEE_PERCENT', default=2.5)
PAYMENT_REDIRECT_URL = env('PAYMENT_REDIRECT_URL', default='https://agricore-frontend.vercel.app/payment/callback')

# Google OAuth: client IDs accepted as ID-token audiences (Android / iOS / web).
# Set GOOGLE_OAUTH_CLIENT_IDS in .env as a comma-separated list to override.
GOOGLE_OAUTH_CLIENT_IDS = env.list(
    'GOOGLE_OAUTH_CLIENT_IDS',
    default=['488596909366-vd5s2k861kn6g1v8e8f3u81eig3h2q2c.apps.googleusercontent.com'],
)



# ==================== API DOCS (drf-spectacular) ====================
REST_FRAMEWORK['DEFAULT_SCHEMA_CLASS'] = 'drf_spectacular.openapi.AutoSchema'

SPECTACULAR_SETTINGS = {
    'TITLE': 'Agricore API',
    'DESCRIPTION': (
        'Backend API for the Agricore agricultural commerce platform: '
        'farms, crops, livestock, inventory, marketplace, escrow payments, '
        'market prices, logistics, workforce, AI, and notifications.'
    ),
    'VERSION': '1.0.0',
    'SERVE_INCLUDE_SCHEMA': False,
}


# --- Weather (Open-Meteo) snapshot cache TTL in minutes ---
WEATHER_CACHE_MINUTES = env.int('WEATHER_CACHE_MINUTES', default=60)

DATABASES['default']['DISABLE_SERVER_SIDE_CURSORS'] = True

# --- Agricore SMS env (idempotent) ---
SMS_PROVIDER = os.environ.get('SMS_PROVIDER', 'console')
AT_USERNAME  = os.environ.get('AT_USERNAME', 'sandbox')
AT_API_KEY   = os.environ.get('AT_API_KEY', '')
AT_SENDER_ID = os.environ.get('AT_SENDER_ID', '')


# --- Agricore IntaSend env (idempotent) ---
PAYMENT_PROVIDER = os.environ.get("PAYMENT_PROVIDER", "intasend")
INTASEND_SECRET_KEY = os.environ.get("INTASEND_SECRET_KEY", "")
INTASEND_PUBLISHABLE_KEY = os.environ.get("INTASEND_PUBLISHABLE_KEY", "")
INTASEND_TEST = os.environ.get("INTASEND_TEST", "True").strip().lower() not in ("0", "false", "no", "")


# --- Agricore IntaSend webhook (idempotent) ---
INTASEND_WEBHOOK_CHALLENGE = os.environ.get("INTASEND_WEBHOOK_CHALLENGE", "")
