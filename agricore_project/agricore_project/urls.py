from django.contrib import admin
from django.urls import path, include, re_path
from .user_settings_api import user_settings
from django.conf import settings
from django.conf.urls.static import static

from rest_framework.routers import DefaultRouter
from rest_framework_nested.routers import NestedSimpleRouter
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView, SpectacularRedocView
from weather.api.views import FarmWeatherView

from accounts.api.views import SPAView
from accounts.views import (
    authentication_view,
    cart_view,
    chat_detail_view,
    chats_view,
    digital_store_view,
    digitalstores_view,
    individual_farm_view,
    marketplace_view,
    multi_farm_view,
    onboarding_view,
    product_detail_view,
    profile_view,
    splashscreen_view,
    workforce_view,
)
from accounts.api.views import (
    CurrentUserView,
    CustomUserViewSet,
    AttachmentViewSet,
    DigitalWalletViewSet,
    SpecializedProfessionalViewSet,
    ReviewViewSet,
    OnboardingProgressViewSet,
    GoogleAuthView,
)

from farms.api.views import FarmViewSet, FieldViewSet
from produce.views import ProduceCollectionViewSet



from livestock.api.views import (
    LivestockUnitViewSet,
    AnimalViewSet,
    AnimalReproductiveRecordViewSet,
    LivestockTaskViewSet,
    LivestockEmployeeAssignmentViewSet,
    LivestockExpenseViewSet,
    AnimalMedicalRecordViewSet,
)

from inventory.api.views import (
    InventoryViewSet,
)

from marketplace.api.views import (
    StoreViewSet,
    ProductViewSet,
    OrderViewSet,
    OrderItemViewSet,
    PaymentViewSet,
    ShippingViewSet,
    AdvertisementViewSet,
    StoreReviewViewSet,
    ProductReviewViewSet,
    PaymentCardViewSet,
)

from workforce.api.views import (
    EmployeeViewSet,
    MachineryViewSet,
    EquipmentViewSet,
    EmployeePerformanceViewSet,
    FiredEmployeeViewSet,
    ProfessionalProfileViewSet,
    ProfessionalReviewViewSet,
    JobPostingViewSet,
    JobApplicationViewSet,
)

from communications.api.views import (
    ConversationViewSet,
    ConversationParticipantViewSet,
    MessageViewSet,
)

from ai.api.views import (
    AILogViewSet,
    AlertViewSet,
    DaleAIChatView,
    CropDiagnosisView,
)

from analytics.api.views import (
    FarmFinanceViewSet,
    AnalyticsAggregateViewSet,
    ReportViewSet,
)

# -------------------------------------------------------------------
# MAIN ROUTER
from crops.api.views import CropCycleViewSet
# -------------------------------------------------------------------

from marketprices.api.views import MarketPriceViewSet
from logistics.api.views import (
    VehicleViewSet,
    TransportRequestViewSet,
    TransportBidViewSet,
)
from escrow.api.views import EscrowViewSet, FlutterwaveWebhookView, PayoutAccountViewSet
from logistics.api.views import TransporterViewSet, DeliveryJobViewSet, TransporterReviewViewSet, RiderLinkView, RiderLinkPickupView, RiderLinkDeliverView, ussd_callback
from notifications.api.views import NotificationViewSet
from expenses.api.views import (
    ExpenseCategoryViewSet,
    ExpenseViewSet,
    ExpenseEventViewSet,
    ExpensePaymentViewSet,
)

router = DefaultRouter()
router.register(r'crop-cycles', CropCycleViewSet, basename='cropcycle')

# Accounts
router.register(r'users', CustomUserViewSet, basename='user')
router.register(r'notifications', NotificationViewSet, basename='notification')
router.register(r'attachments', AttachmentViewSet, basename='attachment')
router.register(r'digital-wallets', DigitalWalletViewSet, basename='digitalwallet')
router.register(r'specialized-professionals', SpecializedProfessionalViewSet, basename='specializedprofessional')
router.register(r'reviews', ReviewViewSet, basename='review')
router.register(r'onboarding-progress', OnboardingProgressViewSet, basename='onboardingprogress')


# Farms
router.register(r'farms', FarmViewSet, basename='farm')
router.register(r'fields', FieldViewSet, basename='field')



# Livestock
router.register(r'livestock-units', LivestockUnitViewSet, basename='livestockunit')
router.register(r'animals', AnimalViewSet, basename='animal')
router.register(r'animal-reproductive-records', AnimalReproductiveRecordViewSet, basename='animalreproductiverecord')
router.register(r'livestock-tasks', LivestockTaskViewSet, basename='livestocktask')
router.register(r'livestock-employee-assignments', LivestockEmployeeAssignmentViewSet, basename='livestockemployeeassignment')
router.register(r'livestock-expenses', LivestockExpenseViewSet, basename='livestockexpense')
router.register(r'animal-medical-records', AnimalMedicalRecordViewSet, basename='animalmedicalrecord')

# Inventory
router.register(r'inventory', InventoryViewSet, basename='inventory')

# Marketplace
router.register(r'stores', StoreViewSet, basename='store')
router.register(r'products', ProductViewSet, basename='product')
router.register(r'orders', OrderViewSet, basename='order')
router.register(r'order-items', OrderItemViewSet, basename='orderitem')
router.register(r'payments', PaymentViewSet, basename='payment')
router.register(r'shippings', ShippingViewSet, basename='shipping')
router.register(r'advertisements', AdvertisementViewSet, basename='advertisement')
router.register(r'store-reviews', StoreReviewViewSet, basename='storereview')
router.register(r'product-reviews', ProductReviewViewSet, basename='productreview')
router.register(r'payment-cards', PaymentCardViewSet, basename='paymentcard')

# Workforce
router.register(r'employees', EmployeeViewSet, basename='employee')
router.register(r'machinery', MachineryViewSet, basename='machinery')
router.register(r'equipment', EquipmentViewSet, basename='equipment')
router.register(r'employee-performances', EmployeePerformanceViewSet, basename='employeeperformance')
router.register(r'fired-employees', FiredEmployeeViewSet, basename='firedemployee')

# Professional Network
router.register(r'professional-profiles', ProfessionalProfileViewSet, basename='professionalprofile')
router.register(r'professional-reviews', ProfessionalReviewViewSet, basename='professionalreview')
router.register(r'job-postings', JobPostingViewSet, basename='jobposting')
router.register(r'job-applications', JobApplicationViewSet, basename='jobapplication')

# Communications
router.register(r'conversations', ConversationViewSet, basename='conversation')
router.register(r'conversation-participants', ConversationParticipantViewSet, basename='conversationparticipant')
router.register(r'messages', MessageViewSet, basename='message')

# AI
router.register(r'ai-logs', AILogViewSet, basename='ailog')
router.register(r'alerts', AlertViewSet, basename='alert')

# Analytics
router.register(r'farm-finances', FarmFinanceViewSet, basename='farmfinance')
router.register(r'analytics-aggregates', AnalyticsAggregateViewSet, basename='analyticsaggregate')
router.register(r'reports', ReportViewSet, basename='report')

# Ecosystem - Phase 1
router.register(r'market-prices', MarketPriceViewSet, basename='marketprice')
router.register(r'vehicles', VehicleViewSet, basename='vehicle')
router.register(r'transport-requests', TransportRequestViewSet, basename='transportrequest')
router.register(r'transport-bids', TransportBidViewSet, basename='transportbid')
router.register(r'escrows', EscrowViewSet, basename='escrow')
router.register(r'transporters', TransporterViewSet, basename='transporter')
router.register(r'delivery-jobs', DeliveryJobViewSet, basename='deliveryjob')
router.register(r'transporter-reviews', TransporterReviewViewSet, basename='transporterreview')
router.register(r'payout-accounts', PayoutAccountViewSet, basename='payoutaccount')

# Expenses
router.register(r'expense-categories', ExpenseCategoryViewSet, basename='expensecategory')
router.register(r'expenses', ExpenseViewSet, basename='expense')
router.register(r'expense-events', ExpenseEventViewSet, basename='expenseevent')
router.register(r'expense-payments', ExpensePaymentViewSet, basename='expensepayment')

# -------------------------------------------------------------------
# NESTED ROUTER: PRODUCE UNDER FARMS
# -------------------------------------------------------------------

farms_router = NestedSimpleRouter(router, r'farms', lookup='farm')
farms_router.register(
    r'produce-collections',
    ProduceCollectionViewSet,
    basename='farm-produce-collections'
)

# -------------------------------------------------------------------
# URL PATTERNS
# -------------------------------------------------------------------

urlpatterns = [
    path('api/schema/', SpectacularAPIView.as_view(), name='schema'),
    path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),
    path('api/redoc/', SpectacularRedocView.as_view(url_name='schema'), name='redoc'),
    path('auth/', authentication_view, name='authentication'),
    path('accounts/login/', __import__('accounts.views').views.login_view, name='login'),
    path('cart/', cart_view, name='cart'),
    path('chat_detail/', chat_detail_view, name='chat_detail'),
    path('chats/', chats_view, name='chats'),
    path('digital_store/', digital_store_view, name='digital_store'),
    path('digitalstores/', digitalstores_view, name='digitalstores'),
    path('individual_farm/', individual_farm_view, name='individual_farm'),
    path('marketplace/', marketplace_view, name='marketplace'),
    path('multi_farm/', multi_farm_view, name='multi_farm'),
    path('onboarding/', onboarding_view, name='onboarding'),
    path('product_detail/', product_detail_view, name='product_detail'),
    path('profile/', profile_view, name='profile'),
    path('splashscreen/', splashscreen_view, name='splashscreen'),
    path('workforce/', workforce_view, name='workforce'),
    path('admin/', admin.site.urls),

    # Farm management dashboard and analytics UI
    path('dashboard/', include('analytics.urls', namespace='analytics')),
    # Livestock and Crops views
    path('livestock/', include('livestock.urls', namespace='livestock')),

    # Farm finance view
    path('analytics/finances/', __import__('analytics.views').views.farm_finance_list, name='farm_finance_list'),

    # JWT Auth
    path('api/auth/token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('api/auth/google/', GoogleAuthView.as_view(), name='google_auth'),

    # Current user (place before router so it doesn't get captured by users/<pk>/)
    path('api/users/me/', CurrentUserView.as_view(), name='current_user'),

    # Weather (per-farm, Open-Meteo)
    path('api/weather/', FarmWeatherView.as_view(), name='farm-weather'),

    # API routes
    path('api/', include(router.urls)),
    path('api/rider-link/<str:token>/', RiderLinkView.as_view()),
    path('api/rider-link/<str:token>/pickup/', RiderLinkPickupView.as_view()),
    path('api/rider-link/<str:token>/deliver/', RiderLinkDeliverView.as_view()),
    path('api/ussd/', ussd_callback),
    path('api/payments/flutterwave/webhook/', FlutterwaveWebhookView.as_view(), name='flw_webhook'),

    # Pesapal API 3.0 (browser redirect flow): /payments/start|callback|ipn
    path('', include('payments.urls')),

    path('api/', include(farms_router.urls)),

    # Dale AI chat
    path('api/ai/dale/ask/', DaleAIChatView.as_view(), name='dale_ai_ask'),
    path('api/ai/diagnose-crop/', CropDiagnosisView.as_view(), name='crop_diagnosis'),

    # SPA Routes
    re_path(r'^$', SPAView.as_view()),
    re_path(r'^(?P<path>.*\.html)$', SPAView.as_view()),
]

# Serve media files in development
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

    # User settings API (must be in urlpatterns, not at top-level)
    urlpatterns.insert(0, path('api/user/settings/', user_settings, name='user_settings'))