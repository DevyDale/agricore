"""Pesapal payment views: start payment, browser callback, server-to-server IPN.

Browser-redirect flow (session auth), mirroring the Pesapal 3.0 walkthrough but
adapted to Agricore's real ``marketplace.Order`` (``total_amount`` / ``buyer`` /
``currency``). The IPN — not the callback — is the source of truth for fulfilment.
"""
import uuid
from decimal import Decimal

from django.conf import settings
from django.contrib.auth.decorators import login_required
from django.db import transaction
from django.http import HttpResponse, HttpResponseForbidden, JsonResponse
from django.shortcuts import get_object_or_404, redirect
from django.views.decorators.csrf import csrf_exempt

from marketplace.models import Order

from .models import PesapalPayment
from .services import pesapal


def _billing_for(buyer, order):
    """Pesapal billing_address from the buyer, with safe fallbacks."""
    full = (getattr(buyer, "get_full_name", lambda: "")() or "").strip()
    first = getattr(buyer, "first_name", "") or (full.split(" ")[0] if full else "Agricore")
    last = getattr(buyer, "last_name", "") or (full.split(" ")[-1] if " " in full else "Buyer")
    return {
        "email_address": getattr(buyer, "email", "") or "buyer@agricore.app",
        "phone_number": str(getattr(buyer, "phone", "") or ""),
        "country_code": getattr(settings, "PESAPAL_COUNTRY_CODE", "UG"),
        "first_name": first,
        "last_name": last,
    }


@login_required
def start_payment(request, order_id):
    """Buyer clicks 'Pay' -> build the Pesapal order and redirect to their page."""
    order = get_object_or_404(Order, id=order_id)
    # Money guard: only the order's own buyer may start its payment.
    if order.buyer_id != request.user.id:
        return HttpResponseForbidden("You can only pay for your own order.")

    ipn_id = getattr(settings, "PESAPAL_IPN_ID", "")
    if not ipn_id:
        return HttpResponse(
            "Pesapal IPN is not configured yet (PESAPAL_IPN_ID is empty). "
            "Register the IPN once with `manage.py register_pesapal_ipn`.",
            status=503,
        )

    # A unique reference per attempt so a retry never collides with a past one.
    merchant_ref = f"AGC-{order.id}-{uuid.uuid4().hex[:10]}"
    payment = PesapalPayment.objects.create(
        order=order,
        merchant_ref=merchant_ref,
        amount=order.total_amount,
        currency=order.currency or "UGX",
    )

    try:
        token = pesapal.get_access_token()
        result = pesapal.submit_order(
            token,
            merchant_ref=merchant_ref,
            amount=float(order.total_amount),
            description=f"Agricore order {order.id}",
            callback_url=request.build_absolute_uri("/payments/callback/"),
            notification_id=ipn_id,
            currency=order.currency or "UGX",
            billing=_billing_for(order.buyer, order),
        )
    except pesapal.PesapalError as e:
        payment.status = "FAILED"
        payment.raw = {"error": str(e)}
        payment.save(update_fields=["status", "raw", "updated_at"])
        return HttpResponse(f"Could not start payment: {e}", status=502)

    payment.order_tracking_id = result["order_tracking_id"]
    payment.redirect_url = result["redirect_url"]
    payment.raw = result
    payment.save(update_fields=["order_tracking_id", "redirect_url", "raw", "updated_at"])

    return redirect(result["redirect_url"])


@login_required
def mock_pay(request, order_id):
    """DEV/DEMO ONLY: mark an order paid and run the real fulfilment path without
    going through Pesapal. Lets you demo the full buyer -> seller -> stock/notify
    flow when the gateway is unavailable or you have no merchant account yet.

    Guarded by settings.PESAPAL_ALLOW_MOCK (defaults to DEBUG) so it can never
    fire in production, plus the usual buyer-ownership check.
    """
    if not getattr(settings, "PESAPAL_ALLOW_MOCK", False):
        return HttpResponseForbidden("Mock payments are disabled.")
    order = get_object_or_404(Order, id=order_id)
    if order.buyer_id != request.user.id:
        return HttpResponseForbidden("You can only pay for your own order.")
    if order.status == "paid":
        return JsonResponse({"status": "paid", "order": order.id, "detail": "already paid"})

    PesapalPayment.objects.create(
        order=order,
        merchant_ref=f"MOCK-{order.id}-{uuid.uuid4().hex[:10]}",
        order_tracking_id=f"MOCK-{uuid.uuid4().hex[:12]}",
        amount=order.total_amount,
        currency=order.currency or "UGX",
        status="COMPLETED",
        raw={"mock": True},
    )
    _fulfil(order)
    return JsonResponse(
        {"status": "paid", "order": order.id, "amount": str(order.total_amount), "currency": order.currency}
    )


def payment_callback(request):
    """Buyer is redirected here after paying. Show a result; do NOT fulfil here."""
    tracking_id = request.GET.get("OrderTrackingId")
    if not tracking_id:
        return HttpResponse("Missing OrderTrackingId.", status=400)
    try:
        token = pesapal.get_access_token()
        status = pesapal.get_transaction_status(token, tracking_id)
    except pesapal.PesapalError as e:
        return HttpResponse(f"Could not read payment status: {e}", status=502)
    return HttpResponse(
        f"Payment status: {status.get('payment_status_description', 'Unknown')}"
    )


@csrf_exempt
def pesapal_ipn(request):
    """Server-to-server notification from Pesapal. THIS is the source of truth."""
    tracking_id = request.GET.get("OrderTrackingId") or request.POST.get("OrderTrackingId")
    merchant_ref = (
        request.GET.get("OrderMerchantReference")
        or request.POST.get("OrderMerchantReference")
    )
    if not tracking_id:
        return JsonResponse({"status": 400, "detail": "missing OrderTrackingId"}, status=200)

    payment = (
        PesapalPayment.objects.filter(order_tracking_id=tracking_id).first()
        or PesapalPayment.objects.filter(merchant_ref=merchant_ref).first()
    )
    if payment is None:
        return JsonResponse({"status": 200, "detail": "unknown reference"}, status=200)

    # Idempotent: if we already settled this attempt, just acknowledge.
    if payment.status == "COMPLETED":
        return _ipn_ack(tracking_id, merchant_ref)

    try:
        token = pesapal.get_access_token()
        result = pesapal.get_transaction_status(token, tracking_id)
    except pesapal.PesapalError as e:
        # Tell Pesapal we couldn't process so it retries later.
        return JsonResponse({"status": 500, "detail": f"verify failed: {e}"}, status=200)

    description = (result.get("payment_status_description") or "").strip()
    payment.raw = result
    if description == "Completed":
        payment.status = "COMPLETED"
        payment.save(update_fields=["status", "raw", "updated_at"])
        _fulfil(payment.order)
    elif description in ("Failed", "Invalid", "Reversed"):
        payment.status = description.upper()
        payment.save(update_fields=["status", "raw", "updated_at"])
    else:
        payment.save(update_fields=["raw", "updated_at"])

    return _ipn_ack(tracking_id, merchant_ref)


def _ipn_ack(tracking_id, merchant_ref):
    """Acknowledge the IPN so Pesapal stops retrying."""
    return JsonResponse(
        {
            "orderNotificationType": "IPNCHANGE",
            "orderTrackingId": tracking_id,
            "orderMerchantReference": merchant_ref,
            "status": 200,
        }
    )


def _fulfil(order):
    """Agricore order fulfilment once payment is confirmed. Idempotent: the IPN's
    COMPLETED guard plus the in-transaction status check ensure it runs once.

    Marks the order paid, writes a ledger row, decrements stock for each item,
    then flags the seller. The same body runs for a real Pesapal IPN and for the
    dev-only mock_pay path, so the demo behaves exactly like production."""
    from marketplace.models import Payment

    with transaction.atomic():
        order = Order.objects.select_for_update().get(pk=order.pk)
        if order.status == "paid":
            return  # already fulfilled
        order.status = "paid"
        order.save(update_fields=["status", "updated_at"])

        # Record the money movement against the marketplace Payment ledger.
        try:
            pp = order.pesapal_payments.filter(status="COMPLETED").first()
            Payment.objects.create(
                order=order,
                amount=order.total_amount,
                method="pesapal",
                provider="pesapal",
                provider_reference=(pp.order_tracking_id if pp else ""),
                status="completed",
            )
        except Exception:
            # Ledger write is best-effort; the order status is the authority.
            pass

        # Decrement stock for each ordered item, never below zero.
        try:
            for item in order.orderitem_set.select_related("product").all():
                product = item.product
                if product is None:
                    continue
                have = Decimal(str(product.stock_quantity or 0))
                sold = Decimal(str(item.quantity or 0))
                product.stock_quantity = max(Decimal("0"), have - sold)
                product.save(update_fields=["stock_quantity", "updated_at"])
        except Exception:
            pass

    # Flag the seller (store owner) that they have a paid order. Best-effort,
    # outside the transaction so a notifications hiccup can't undo fulfilment.
    try:
        from notifications.models import Notification

        Notification.objects.create(
            recipient=order.store.owner,
            category="payment",
            title="Payment received",
            body=f"Order #{order.id} has been paid ({order.currency} {order.total_amount}).",
            related_table="order",
            related_id=order.id,
        )
    except Exception:
        pass
