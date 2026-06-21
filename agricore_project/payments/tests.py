"""End-to-end tests for the Pesapal flow.

These stub the Pesapal HTTP calls (their sandbox is frequently down), so they
prove *our* integration: start_payment builds the order and redirects, the IPN
verifies server-side and fulfils the order exactly once, and the marketplace
ledger row is written.
"""
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.urls import reverse

from marketplace.models import Order, OrderItem, Payment, Product, Store

from payments.models import PesapalPayment

User = get_user_model()


class PesapalFlowTests(TestCase):
    def setUp(self):
        self.buyer = User.objects.create_user(
            username="buyer", email="buyer@test.app", password="pw12345!"
        )
        self.other = User.objects.create_user(
            username="other", email="other@test.app", password="pw12345!"
        )
        self.store = Store.objects.create(owner=self.buyer, name="Test Stall")
        self.order = Order.objects.create(
            buyer=self.buyer,
            store=self.store,
            total_amount=Decimal("15000.00"),
            currency="UGX",
            status="pending",
        )

    # ---- start_payment ----
    @mock.patch("payments.views.pesapal.submit_order")
    @mock.patch("payments.views.pesapal.get_access_token", return_value="tok")
    def test_start_payment_redirects_and_records(self, _tok, submit):
        submit.return_value = {
            "order_tracking_id": "TRACK-123",
            "merchant_reference": "AGC-x",
            "redirect_url": "https://pay.example/checkout/TRACK-123",
        }
        with self.settings(PESAPAL_IPN_ID="ipn-1"):
            self.client.force_login(self.buyer)
            resp = self.client.get(reverse("payments:start_payment", args=[self.order.id]))
        self.assertEqual(resp.status_code, 302)
        self.assertEqual(resp["Location"], "https://pay.example/checkout/TRACK-123")
        pp = PesapalPayment.objects.get(order=self.order)
        self.assertEqual(pp.order_tracking_id, "TRACK-123")
        self.assertEqual(pp.status, "PENDING")
        # amount sent to Pesapal matches the server-side order total
        self.assertEqual(submit.call_args.kwargs["amount"], 15000.0)

    def test_start_payment_blocks_non_buyer(self):
        with self.settings(PESAPAL_IPN_ID="ipn-1"):
            self.client.force_login(self.other)
            resp = self.client.get(reverse("payments:start_payment", args=[self.order.id]))
        self.assertEqual(resp.status_code, 403)
        self.assertFalse(PesapalPayment.objects.exists())

    def test_start_payment_requires_ipn_configured(self):
        with self.settings(PESAPAL_IPN_ID=""):
            self.client.force_login(self.buyer)
            resp = self.client.get(reverse("payments:start_payment", args=[self.order.id]))
        self.assertEqual(resp.status_code, 503)

    # ---- IPN ----
    def _pending_payment(self):
        return PesapalPayment.objects.create(
            order=self.order,
            merchant_ref="AGC-ref-1",
            order_tracking_id="TRACK-123",
            amount=self.order.total_amount,
            currency="UGX",
        )

    @mock.patch("payments.views.pesapal.get_transaction_status")
    @mock.patch("payments.views.pesapal.get_access_token", return_value="tok")
    def test_ipn_completed_fulfils_once(self, _tok, status):
        status.return_value = {"payment_status_description": "Completed"}
        self._pending_payment()
        url = reverse("payments:pesapal_ipn")
        params = {"OrderTrackingId": "TRACK-123", "OrderMerchantReference": "AGC-ref-1"}

        r1 = self.client.get(url, params)
        self.assertEqual(r1.status_code, 200)
        self.assertEqual(r1.json()["status"], 200)

        self.order.refresh_from_db()
        self.assertEqual(self.order.status, "paid")
        self.assertEqual(PesapalPayment.objects.get(merchant_ref="AGC-ref-1").status, "COMPLETED")
        self.assertEqual(Payment.objects.filter(order=self.order).count(), 1)

        # Second delivery of the same IPN must NOT double-fulfil.
        r2 = self.client.get(url, params)
        self.assertEqual(r2.status_code, 200)
        self.assertEqual(Payment.objects.filter(order=self.order).count(), 1)
        # status is only fetched once (second call short-circuits on COMPLETED)
        self.assertEqual(status.call_count, 1)

    @mock.patch("payments.views.pesapal.get_transaction_status")
    @mock.patch("payments.views.pesapal.get_access_token", return_value="tok")
    def test_ipn_failed_does_not_fulfil(self, _tok, status):
        status.return_value = {"payment_status_description": "Failed"}
        self._pending_payment()
        self.client.get(
            reverse("payments:pesapal_ipn"),
            {"OrderTrackingId": "TRACK-123", "OrderMerchantReference": "AGC-ref-1"},
        )
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, "pending")
        self.assertEqual(PesapalPayment.objects.get(merchant_ref="AGC-ref-1").status, "FAILED")
        self.assertFalse(Payment.objects.filter(order=self.order).exists())

    def test_ipn_unknown_reference_is_acknowledged(self):
        resp = self.client.get(
            reverse("payments:pesapal_ipn"),
            {"OrderTrackingId": "NOPE", "OrderMerchantReference": "NOPE"},
        )
        self.assertEqual(resp.status_code, 200)

    # ---- mock pay (dev/demo) ----
    def test_mock_pay_fulfils_with_stock_and_notification(self):
        from notifications.models import Notification

        product = Product.objects.create(
            store=self.store, title="Maize", category="Crops",
            price=Decimal("500.00"), stock_quantity=Decimal("10"), unit="kg",
        )
        OrderItem.objects.create(
            order=self.order, product=product, quantity=Decimal("3"),
            price_per_unit=Decimal("500.00"), subtotal=Decimal("1500.00"),
        )
        with self.settings(PESAPAL_ALLOW_MOCK=True):
            self.client.force_login(self.buyer)
            resp = self.client.get(reverse("payments:mock_pay", args=[self.order.id]))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["status"], "paid")

        self.order.refresh_from_db()
        product.refresh_from_db()
        self.assertEqual(self.order.status, "paid")
        self.assertEqual(product.stock_quantity, Decimal("7"))  # 10 - 3
        self.assertEqual(Payment.objects.filter(order=self.order).count(), 1)
        self.assertTrue(
            Notification.objects.filter(
                recipient=self.store.owner, category="payment", related_id=self.order.id
            ).exists()
        )

    def test_mock_pay_disabled_returns_403(self):
        with self.settings(PESAPAL_ALLOW_MOCK=False):
            self.client.force_login(self.buyer)
            resp = self.client.get(reverse("payments:mock_pay", args=[self.order.id]))
        self.assertEqual(resp.status_code, 403)
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, "pending")
