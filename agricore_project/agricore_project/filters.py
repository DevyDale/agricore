"""
Django-filter configurations for Agricore API
"""
from django_filters import rest_framework as filters
from farms.models import Farm, Field
from crops.models import Crop, CropTask
from livestock.models import Animal, LivestockTask, LivestockUnit
from marketplace.models import Store, Product, Order
from workforce.models import JobPosting, JobApplication, ProfessionalProfile
from ai.models import Alert
from inventory.models import Inventory
from produce.models import ProduceCollection


class FarmFilter(filters.FilterSet):
    """Filter for farms"""
    type = filters.CharFilter(lookup_expr='iexact')
    country = filters.CharFilter(lookup_expr='icontains')
    city = filters.CharFilter(lookup_expr='icontains')
    created_after = filters.DateFilter(field_name='created_at', lookup_expr='gte')
    created_before = filters.DateFilter(field_name='created_at', lookup_expr='lte')
    
    class Meta:
        model = Farm
        fields = ['type', 'country', 'city']


class CropFilter(filters.FilterSet):
    """Filter for crops"""
    status = filters.CharFilter(lookup_expr='iexact')
    field = filters.NumberFilter()
    farm = filters.NumberFilter(field_name='field__farm')
    
    class Meta:
        model = Crop
        fields = ['status', 'field']


class CropTaskFilter(filters.FilterSet):
    """Filter for crop tasks"""
    status = filters.CharFilter(lookup_expr='iexact')
    crop = filters.NumberFilter()
    due_date_after = filters.DateFilter(field_name='due_date', lookup_expr='gte')
    due_date_before = filters.DateFilter(field_name='due_date', lookup_expr='lte')
    overdue = filters.BooleanFilter(method='filter_overdue')
    
    def filter_overdue(self, queryset, name, value):
        from django.utils import timezone
        if value:
            return queryset.filter(due_date__lt=timezone.now().date(), status__ne='completed')
        return queryset
    
    class Meta:
        model = CropTask
        fields = ['status', 'crop', 'due_date']


class AnimalFilter(filters.FilterSet):
    """Filter for animals"""
    livestock_unit = filters.NumberFilter()
    status = filters.CharFilter(lookup_expr='iexact')
    sex = filters.CharFilter(lookup_expr='iexact')
    age_group = filters.CharFilter(lookup_expr='iexact')
    health_score_min = filters.NumberFilter(field_name='health_score', lookup_expr='gte')
    health_score_max = filters.NumberFilter(field_name='health_score', lookup_expr='lte')
    
    class Meta:
        model = Animal
        fields = ['livestock_unit', 'status', 'sex', 'age_group']


class LivestockTaskFilter(filters.FilterSet):
    """Filter for livestock tasks"""
    status = filters.CharFilter(lookup_expr='iexact')
    livestock_unit = filters.NumberFilter()
    due_date_after = filters.DateFilter(field_name='due_date', lookup_expr='gte')
    due_date_before = filters.DateFilter(field_name='due_date', lookup_expr='lte')
    
    class Meta:
        model = LivestockTask
        fields = ['status', 'livestock_unit', 'due_date']


class StoreFilter(filters.FilterSet):
    """Filter for stores"""
    is_verified = filters.BooleanFilter()
    farm = filters.NumberFilter()
    rating_min = filters.NumberFilter(field_name='rating', lookup_expr='gte')
    
    class Meta:
        model = Store
        fields = ['is_verified', 'farm']


class ProductFilter(filters.FilterSet):
    """Filter for products"""
    store = filters.NumberFilter()
    category = filters.CharFilter(lookup_expr='iexact')
    price_min = filters.NumberFilter(field_name='price', lookup_expr='gte')
    price_max = filters.NumberFilter(field_name='price', lookup_expr='lte')
    in_stock = filters.BooleanFilter(method='filter_in_stock')
    search = filters.CharFilter(method='search_products')
    
    def filter_in_stock(self, queryset, name, value):
        if value:
            return queryset.filter(stock_quantity__gt=0)
        return queryset
    
    def search_products(self, queryset, name, value):
        return queryset.filter(name__icontains=value) | queryset.filter(description__icontains=value)
    
    class Meta:
        model = Product
        fields = ['store', 'category']


class OrderFilter(filters.FilterSet):
    """Filter for orders"""
    status = filters.CharFilter(lookup_expr='iexact')
    buyer = filters.NumberFilter()
    store = filters.NumberFilter()
    created_after = filters.DateFilter(field_name='created_at', lookup_expr='gte')
    created_before = filters.DateFilter(field_name='created_at', lookup_expr='lte')
    
    class Meta:
        model = Order
        fields = ['status', 'buyer', 'store']


class JobPostingFilter(filters.FilterSet):
    """Filter for job postings"""
    status = filters.CharFilter(lookup_expr='iexact')
    specialty_required = filters.CharFilter(lookup_expr='iexact')
    payment_type = filters.CharFilter(lookup_expr='iexact')
    budget_min = filters.NumberFilter(field_name='budget', lookup_expr='gte')
    budget_max = filters.NumberFilter(field_name='budget', lookup_expr='lte')
    start_date_after = filters.DateFilter(field_name='start_date', lookup_expr='gte')
    location = filters.CharFilter(lookup_expr='icontains')
    
    class Meta:
        model = JobPosting
        fields = ['status', 'specialty_required', 'payment_type']


class JobApplicationFilter(filters.FilterSet):
    """Filter for job applications"""
    status = filters.CharFilter(lookup_expr='iexact')
    job = filters.NumberFilter()
    professional = filters.NumberFilter()
    
    class Meta:
        model = JobApplication
        fields = ['status', 'job', 'professional']


class ProfessionalProfileFilter(filters.FilterSet):
    """Filter for professional profiles"""
    specialty = filters.CharFilter(lookup_expr='iexact')
    availability = filters.CharFilter(lookup_expr='iexact')
    is_verified = filters.BooleanFilter()
    is_active = filters.BooleanFilter()
    featured = filters.BooleanFilter()
    experience_min = filters.NumberFilter(field_name='years_experience', lookup_expr='gte')
    rate_max = filters.NumberFilter(field_name='hourly_rate', lookup_expr='lte')
    rating_min = filters.NumberFilter(field_name='average_rating', lookup_expr='gte')
    location = filters.CharFilter(lookup_expr='icontains')
    
    class Meta:
        model = ProfessionalProfile
        fields = ['specialty', 'availability', 'is_verified', 'is_active', 'featured']


class AlertFilter(filters.FilterSet):
    """Filter for alerts"""
    farm = filters.NumberFilter()
    type = filters.CharFilter(lookup_expr='iexact')
    resolved = filters.BooleanFilter()
    created_after = filters.DateFilter(field_name='created_at', lookup_expr='gte')
    
    class Meta:
        model = Alert
        fields = ['farm', 'type', 'resolved']


class InventoryFilter(filters.FilterSet):
    """Filter for inventory"""
    farm = filters.NumberFilter()
    category = filters.CharFilter(lookup_expr='iexact')
    low_stock = filters.BooleanFilter(method='filter_low_stock')
    
    def filter_low_stock(self, queryset, name, value):
        if value:
            return queryset.filter(quantity__lte=filters.F('reorder_threshold'))
        return queryset
    
    class Meta:
        model = Inventory
        fields = ['farm', 'category']


class ProduceCollectionFilter(filters.FilterSet):
    """Filter for produce collections"""
    farm = filters.NumberFilter()
    source = filters.CharFilter(lookup_expr='iexact')
    collection_date_after = filters.DateFilter(field_name='collection_date', lookup_expr='gte')
    collection_date_before = filters.DateFilter(field_name='collection_date', lookup_expr='lte')
    
    class Meta:
        model = ProduceCollection
        fields = ['farm', 'source']
