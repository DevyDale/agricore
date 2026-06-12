from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated, IsAdminUser
from marketprices.models import MarketPrice
from .serializers import MarketPriceSerializer


class MarketPriceViewSet(viewsets.ModelViewSet):
    """Read for any authenticated user; writes restricted to staff,
    since prices are shared reference data, not per-user records.

    Optional filters: ?commodity=Maize&country=Kenya
    """

    queryset = MarketPrice.objects.all()
    serializer_class = MarketPriceSerializer

    def get_permissions(self):
        if self.action in ("list", "retrieve"):
            return [IsAuthenticated()]
        return [IsAdminUser()]

    def get_queryset(self):
        qs = MarketPrice.objects.all()
        commodity = self.request.query_params.get("commodity")
        country = self.request.query_params.get("country")
        price_type = self.request.query_params.get("price_type")
        if commodity:
            qs = qs.filter(commodity__iexact=commodity)
        if country:
            qs = qs.filter(country__iexact=country)
        if price_type:
            qs = qs.filter(price_type=price_type)
        return qs
