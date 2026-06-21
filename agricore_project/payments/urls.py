from django.urls import path

from . import views

app_name = "payments"

urlpatterns = [
    path("payments/start/<int:order_id>/", views.start_payment, name="start_payment"),
    path("payments/callback/", views.payment_callback, name="payment_callback"),
    path("payments/ipn/", views.pesapal_ipn, name="pesapal_ipn"),
]
