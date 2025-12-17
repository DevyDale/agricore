import logging
from django.db import models
from django.db.models import Q
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from rest_framework.decorators import action
from rest_framework.response import Response
from marketplace.models import Store, Product, Order, OrderItem, Payment, Shipping, Advertisement, StoreReview, ProductReview, PaymentCard
from .serializers import StoreSerializer, ProductSerializer, OrderSerializer, OrderItemSerializer, PaymentSerializer, ShippingSerializer, AdvertisementSerializer, StoreReviewSerializer, ProductReviewSerializer, PaymentCardSerializer

class StoreViewSet(viewsets.ModelViewSet):
    queryset = Store.objects.all()
    serializer_class = StoreSerializer
    permission_classes = [IsAuthenticated]

    logger = logging.getLogger(__name__)

    def get_queryset(self):
        user = self.request.user
        # Show stores owned by the user OR linked to a farm owned by the user.
        qs = self.queryset.filter(Q(owner=user) | Q(farm__owner=user))
        # Allow filtering stores by farm via query param ?farm=<id>
        farm_id = self.request.query_params.get('farm')
        if farm_id:
            try:
                qs = qs.filter(farm_id=int(farm_id))
            except (TypeError, ValueError):
                pass
        return qs

    def create(self, request, *args, **kwargs):
        # Ensure the caller is authenticated (permission_classes should enforce this,
        # but handle gracefully if not to avoid DB integrity errors when owner is null).
        if not getattr(request, 'user', None) or not request.user.is_authenticated:
            from rest_framework.response import Response
            from rest_framework import status
            return Response({'detail': 'Authentication credentials were not provided.'}, status=status.HTTP_401_UNAUTHORIZED)

        # Log for debugging: who is creating and what data arrives
        try:
            self.logger.debug('StoreViewSet.create called user=%s authenticated=%s id=%s data=%s',
                              request.user, getattr(request.user, 'is_authenticated', False), getattr(request.user, 'id', None), dict(request.data))
        except Exception:
            pass

        data = request.data.copy()
        # The frontend sends 'verified', but the model field is 'is_verified'.
        # We need to map it here OR rename the model/serializer field.
        # Let's map it for now.
        # Map 'verified' (from frontend payload) to 'is_verified' (in model)
        if 'verified' in data:
            data['is_verified'] = data.pop('verified')
        # The other fields like owner_name, owner_phone, etc., will be handled by the serializer
        # based on the incoming JSON payload.
        serializer = self.get_serializer(data=data)
        serializer.is_valid(raise_exception=True)
        # Ensure owner is set during save (owner is read_only in serializer so passing it in data is ignored)
        try:
            instance = serializer.save(owner=request.user)
        except Exception as exc:
            # Log useful debug info and return a controlled error instead of a 500
            import traceback
            traceback.print_exc()
            from rest_framework.response import Response
            from rest_framework import status
            return Response({'detail': 'Failed to create store', 'error': str(exc), 'validated_data': serializer.validated_data}, status=status.HTTP_400_BAD_REQUEST)
        headers = self.get_success_headers(self.get_serializer(instance).data)
        from rest_framework.response import Response
        return Response(self.get_serializer(instance).data, status=201, headers=headers)

    def perform_create(self, serializer):
        # Ensure that any code path that calls perform_create (super().create) will set owner
        try:
            serializer.save(owner=self.request.user)
        except Exception:
            # Re-raise so the caller handles it; we've already got guarded handling in create
            raise
    
class ProductViewSet(viewsets.ModelViewSet):
    queryset = Product.objects.all()
    serializer_class = ProductSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = self.queryset.filter(store__owner=self.request.user)
        store_id = self.request.query_params.get('store')
        if store_id:
            try:
                qs = qs.filter(store_id=int(store_id))
            except ValueError:
                pass
        qs = self.queryset.select_related('store', 'store__owner')

        # Annotate ratings
        qs = qs.annotate(
            average_rating=models.Avg('product_reviews__rating'),
            reviews_count=models.Count('product_reviews'),
        )

        # Only restrict to owner for unsafe methods
        if self.request.method not in ('GET', 'HEAD', 'OPTIONS'):
            qs = qs.filter(store__owner=self.request.user)

        store_id = self.request.query_params.get('store')
        if store_id:
            try:
                qs = qs.filter(store_id=int(store_id))
            except (TypeError, ValueError):
                pass

        q = self.request.query_params.get('q')
        if q:
            qs = qs.filter(models.Q(title__icontains=q) | models.Q(description__icontains=q))

        category = self.request.query_params.get('category')
        if category:
            qs = qs.filter(category__iexact=category)

        min_price = self.request.query_params.get('min_price')
        if min_price:
            try:
                qs = qs.filter(price__gte=float(min_price))
            except ValueError:
                pass

        max_price = self.request.query_params.get('max_price')
        if max_price:
            try:
                qs = qs.filter(price__lte=float(max_price))
            except ValueError:
                pass

        ordering = self.request.query_params.get('ordering')
        if ordering in ['price', '-price', '-created_at', 'created_at']:
            qs = qs.order_by(ordering)

        return qs

    def create(self, request, *args, **kwargs):
        """Create product with optional source_produce linking.
        If source_produce is provided, validate that the produce belongs to a farm owned
        by the current user and optionally set the store.farm to the produce farm.
        """
        data = request.data.copy()
        store_id = data.get('store')
        source_produce_id = data.get('source_produce')

        # Validate store ownership
        if store_id:
            try:
                store = Store.objects.get(pk=store_id)
            except Store.DoesNotExist:
                from rest_framework.response import Response
                from rest_framework import status
                return Response({'detail': 'Store not found.'}, status=status.HTTP_404_NOT_FOUND)

            if store.owner != request.user:
                from rest_framework.response import Response
                from rest_framework import status
                return Response({'detail': 'Cannot create products for stores you do not own.'}, status=status.HTTP_403_FORBIDDEN)
        else:
            store = None

        if source_produce_id:
            from produce.models import ProduceCollection
            try:
                produce = ProduceCollection.objects.get(pk=source_produce_id)
            except ProduceCollection.DoesNotExist:
                from rest_framework.response import Response
                from rest_framework import status
                return Response({'detail': 'Source produce not found.'}, status=status.HTTP_404_NOT_FOUND)
            # Validate the produce farm owner matches the requesting user
            if not produce.farm or produce.farm.owner != request.user:
                from rest_framework.response import Response
                from rest_framework import status
                return Response({'detail': 'Source produce does not belong to your farm.'}, status=status.HTTP_403_FORBIDDEN)
            # If the store has no farm linking, attach this farm to it
            if store and (not store.farm):
                store.farm = produce.farm
                store.save()

        return super().create(request, *args, **kwargs)

class OrderViewSet(viewsets.ModelViewSet):
    queryset = Order.objects.all()
    serializer_class = OrderSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(buyer=self.request.user)  # Or store__owner for sellers

class OrderItemViewSet(viewsets.ModelViewSet):
    queryset = OrderItem.objects.all()
    serializer_class = OrderItemSerializer
    permission_classes = [IsAuthenticated]

class PaymentViewSet(viewsets.ModelViewSet):
    queryset = Payment.objects.all()
    serializer_class = PaymentSerializer
    permission_classes = [IsAuthenticated]

class ShippingViewSet(viewsets.ModelViewSet):
    queryset = Shipping.objects.all()
    serializer_class = ShippingSerializer
    permission_classes = [IsAuthenticated]

class AdvertisementViewSet(viewsets.ModelViewSet):
    queryset = Advertisement.objects.all()
    serializer_class = AdvertisementSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        qs = self.queryset.filter(store__owner=user)
        store_id = self.request.query_params.get('store')
        if store_id:
            try:
                qs = qs.filter(store_id=int(store_id))
            except (TypeError, ValueError):
                pass
        return qs

    def perform_create(self, serializer):
        # Calculate end_date based on duration_days
        from datetime import timedelta
        from django.utils import timezone
        duration_days = serializer.validated_data.get('duration_days', 1)
        end_date = timezone.now() + timedelta(days=duration_days)
        serializer.save(end_date=end_date)

    @action(detail=False, methods=['get'], permission_classes=[])
    def active(self, request):
        """Public endpoint to fetch currently active advertisements."""
        from django.utils import timezone
        now = timezone.now()
        qs = Advertisement.objects.filter(is_active=True, end_date__gte=now).select_related('store')
        serializer = self.get_serializer(qs, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def track_impression(self, request, pk=None):
        ad = self.get_object()
        ad.impressions += 1
        ad.save()
        return Response({'impressions': ad.impressions})

    @action(detail=True, methods=['post'])
    def track_click(self, request, pk=None):
        ad = self.get_object()
        ad.clicks += 1
        ad.save()
        return Response({'clicks': ad.clicks})

class StoreReviewViewSet(viewsets.ModelViewSet):
    queryset = StoreReview.objects.all()
    serializer_class = StoreReviewSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = self.queryset.all()
        store_id = self.request.query_params.get('store')
        if store_id:
            try:
                qs = qs.filter(store_id=int(store_id))
            except (TypeError, ValueError):
                pass
        return qs

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

class ProductReviewViewSet(viewsets.ModelViewSet):
    queryset = ProductReview.objects.all()
    serializer_class = ProductReviewSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = self.queryset.all()
        product_id = self.request.query_params.get('product')
        if product_id:
            try:
                qs = qs.filter(product_id=int(product_id))
            except (TypeError, ValueError):
                pass
        return qs

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

class PaymentCardViewSet(viewsets.ModelViewSet):
    queryset = PaymentCard.objects.all()
    serializer_class = PaymentCardSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)