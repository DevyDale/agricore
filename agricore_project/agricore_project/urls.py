from django.contrib import admin
from django.urls import path, include, re_path
from django.conf import settings
from django.conf.urls.static import static

from rest_framework.routers import DefaultRouter
from rest_framework_nested.routers import NestedSimpleRouter # pyright: ignore[reportMissingImports]
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from accounts.api.views import SPAView
from accounts.api.views import (
    CurrentUserView,
    CustomUserViewSet,
    AttachmentViewSet,
    DigitalWalletViewSet,
    SpecializedProfessionalViewSet,
    ReviewViewSet,
    OnboardingProgressViewSet,
)

from farms.api.views import FarmViewSet
from produce.views import ProduceCollectionViewSet

from crops.api.views import (
    CropViewSet,
    CropTaskViewSet,
    CropEmployeeAssignmentViewSet,
    CropExpenseViewSet,
)

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
    ProductionRecordViewSet,
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
    PredictionViewSet,
    AlertViewSet,
    DaleAIChatView,
)

from analytics.api.views import (
    FarmFinanceViewSet,
    AnalyticsAggregateViewSet,
    ReportViewSet,
)

# -------------------------------------------------------------------
# MAIN ROUTER
# -------------------------------------------------------------------

router = DefaultRouter()

# Accounts
router.register(r'users', CustomUserViewSet, basename='user')
router.register(r'attachments', AttachmentViewSet, basename='attachment')
router.register(r'digital-wallets', DigitalWalletViewSet, basename='digitalwallet')
router.register(r'specialized-professionals', SpecializedProfessionalViewSet, basename='specializedprofessional')
router.register(r'reviews', ReviewViewSet, basename='review')
router.register(r'onboarding-progress', OnboardingProgressViewSet, basename='onboardingprogress')

# Farms
router.register(r'farms', FarmViewSet, basename='farm')

# Crops
router.register(r'crops', CropViewSet, basename='crop')
router.register(r'crop-tasks', CropTaskViewSet, basename='croptask')
router.register(r'crop-employee-assignments', CropEmployeeAssignmentViewSet, basename='cropemployeeassignment')
router.register(r'crop-expenses', CropExpenseViewSet, basename='cropexpense')

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
router.register(r'production-records', ProductionRecordViewSet, basename='productionrecord')

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
router.register(r'predictions', PredictionViewSet, basename='prediction')
router.register(r'alerts', AlertViewSet, basename='alert')

# Analytics
router.register(r'farm-finances', FarmFinanceViewSet, basename='farmfinance')
router.register(r'analytics-aggregates', AnalyticsAggregateViewSet, basename='analyticsaggregate')
router.register(r'reports', ReportViewSet, basename='report')

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
    path('admin/', admin.site.urls),

    # JWT Auth
    path('api/auth/token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),

    # Current user (place before router so it doesn't get captured by users/<pk>/)
    path('api/users/me/', CurrentUserView.as_view(), name='current_user'),

    # API routes
    path('api/', include(router.urls)),
    path('api/', include(farms_router.urls)),

    # Dale AI chat
    path('api/ai/dale/ask/', DaleAIChatView.as_view(), name='dale_ai_ask'),

    # SPA Routes
    re_path(r'^$', SPAView.as_view()),
    re_path(r'^(?P<path>.*\.html)$', SPAView.as_view()),
]

# Serve media files in development
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)