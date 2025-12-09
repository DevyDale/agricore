from django.contrib import admin
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from accounts.api.views import (
    CustomUserViewSet,
    AttachmentViewSet,
    DigitalWalletViewSet,
    SpecializedProfessionalViewSet,
    ReviewViewSet,
    OnboardingProgressViewSet,
)

from farms.api.views import (
    FarmViewSet,
    FieldViewSet,
    EnvironmentalDataViewSet,
)

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
)

from workforce.api.views import (
    EmployeeViewSet,
    MachineryViewSet,
    EquipmentViewSet,
    EmployeePerformanceViewSet,
    FiredEmployeeViewSet,
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
)

from analytics.api.views import (
    FarmFinanceViewSet,
    AnalyticsAggregateViewSet,
    ReportViewSet,
)

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
router.register(r'fields', FieldViewSet, basename='field')
router.register(r'environmental-data', EnvironmentalDataViewSet, basename='environmentaldata')

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

# Workforce
router.register(r'employees', EmployeeViewSet, basename='employee')
router.register(r'machinery', MachineryViewSet, basename='machinery')
router.register(r'equipment', EquipmentViewSet, basename='equipment')
router.register(r'employee-performances', EmployeePerformanceViewSet, basename='employeeperformance')
router.register(r'fired-employees', FiredEmployeeViewSet, basename='firedemployee')

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

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/auth/token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('api/', include(router.urls)),
]