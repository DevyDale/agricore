from django.contrib import admin
from logistics.models import Vehicle, TransportRequest, TransportBid

admin.site.register(Vehicle)
admin.site.register(TransportRequest)
admin.site.register(TransportBid)
