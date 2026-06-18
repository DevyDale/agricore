"""Verified Trade Chain — escrow tests.

Covers the escrow state machine (issue delivery code -> confirm delivery ->
dispute) and the split payout. Flutterwave is mocked so no network/transfer
happens. Run with:  python manage.py test escrow --keepdb
"""
from decimal import Decimal
from unittest.mock import patch

from django.test import TestCase
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

from marketplace.models import Store, Order
from escrow.models import Escrow, PaymentTransaction, PayoutAccount

User = get_user_model()


def make_user(username, email):
    # CustomUser.email is unique, so callers pass a distinct email per user.
    return User.objects.create_user(
        username=username, email=email, password="pw12345!", phone="0772000000"
    )


class EscrowFlowTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.buyer = make_user("buyer1", "buyer1@example.com")
        self.seller = make_user("seller1", "seller1@example.com")
        self.store = Store.objects.create(
            owner=self.seller, name="Test Store",
            owner_name="Seller One", owner_phone="0772111111",
        )
        self.order = Order.objects.create(
            buyer=self.buyer, store=self.store,
            total_amount=Decimal("100000"), status="paid",
        )
        self.escrow = Escrow.objects.create(
            order=self.order, buyer=self.buyer,
            amount=Decimal("100000"), currency="UGX", status="held",
        )
        PayoutAccount.objects.create(
            user=self.seller, method="momo", account_bank="MPS",
            account_number="0772111111", account_name="Seller One", network="MTN",
        )

    def test_seller_issues_delivery_code(self):
        self.client.force_authenticate(self.seller)
        r = self.client.post(f"/api/escrows/{self.escrow.id}/issue_otp/", {}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.escrow.refresh_from_db()
        self.assertTrue(self.escrow.delivery_otp)
        self.assertIsNotNone(self.escrow.otp_issued_at)

    def test_buyer_cannot_issue_code(self):
        self.client.force_authenticate(self.buyer)
        r = self.client.post(f"/api/escrows/{self.escrow.id}/issue_otp/", {}, format="json")
        self.assertEqual(r.status_code, 403, r.content)

    def test_confirm_delivery_requires_correct_code(self):
        self.client.force_authenticate(self.seller)
        self.client.post(f"/api/escrows/{self.escrow.id}/issue_otp/", {}, format="json")
        self.escrow.refresh_from_db()

        wrong = self.client.post(
            f"/api/escrows/{self.escrow.id}/confirm_delivery/",
            {"otp": "000000"}, format="json",
        )
        self.assertEqual(wrong.status_code, 400, wrong.content)

        right = self.client.post(
            f"/api/escrows/{self.escrow.id}/confirm_delivery/",
            {"otp": self.escrow.delivery_otp}, format="json",
        )
        self.assertEqual(right.status_code, 200, right.content)
        self.escrow.refresh_from_db()
        self.order.refresh_from_db()
        self.assertIsNotNone(self.escrow.delivered_confirmed_at)
        self.assertIsNotNone(self.escrow.dispute_deadline)
        self.assertEqual(self.order.status, "delivered")

    def test_buyer_can_dispute(self):
        self.client.force_authenticate(self.buyer)
        r = self.client.post(
            f"/api/escrows/{self.escrow.id}/dispute/",
            {"reason": "Short weight"}, format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)
        self.escrow.refresh_from_db()
        self.assertEqual(self.escrow.status, "disputed")


class PayoutSplitTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.buyer = make_user("buyer2", "buyer2@example.com")
        self.seller = make_user("seller2", "seller2@example.com")
        self.store = Store.objects.create(
            owner=self.seller, name="Split Store",
            owner_name="Seller Two", owner_phone="0772222222",
        )
        self.order = Order.objects.create(
            buyer=self.buyer, store=self.store,
            total_amount=Decimal("100000"), status="paid",
        )
        self.escrow = Escrow.objects.create(
            order=self.order, buyer=self.buyer,
            amount=Decimal("100000"), currency="UGX", status="held",
        )
        PayoutAccount.objects.create(
            user=self.seller, method="momo", account_bank="MPS",
            account_number="0772222222", account_name="Seller Two", network="MTN",
        )

    @patch("utils.flutterwave.initiate_transfer")
    @patch("utils.flutterwave.new_tx_ref")
    def test_release_pays_seller_when_no_rider(self, mock_ref, mock_transfer):
        mock_ref.side_effect = lambda prefix: prefix + "-ref"
        mock_transfer.return_value = {"data": {"id": "flw1", "status": "NEW"}}
        self.client.force_authenticate(self.buyer)
        r = self.client.post(f"/api/escrows/{self.escrow.id}/release/", {}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        payouts = PaymentTransaction.objects.filter(escrow=self.escrow, kind="payout")
        self.assertEqual(payouts.count(), 1)
        self.assertEqual(payouts.first().amount, Decimal("100000.00"))

    @patch("utils.flutterwave.initiate_transfer")
    @patch("utils.flutterwave.new_tx_ref")
    def test_release_splits_rider_fee_out_of_seller_proceeds(self, mock_ref, mock_transfer):
        mock_ref.side_effect = lambda prefix: prefix + "-ref"
        mock_transfer.return_value = {"data": {"id": "flw1", "status": "NEW"}}
        from logistics.models import Transporter, DeliveryJob

        rider = make_user("rider2", "rider2@example.com")
        transporter = Transporter.objects.create(
            user=rider, vehicle_type="boda", phone="0772333333",
        )
        DeliveryJob.objects.create(
            order=self.order, escrow=self.escrow, created_by=self.seller,
            transporter=transporter, offered_fee=Decimal("5000"),
            currency="UGX", status="picked_up", pickup_code="123456",
        )
        PayoutAccount.objects.create(
            user=rider, method="momo", account_bank="MPS",
            account_number="0772333333", account_name="Rider Two", network="MTN",
        )
        self.client.force_authenticate(self.buyer)
        r = self.client.post(f"/api/escrows/{self.escrow.id}/release/", {}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        amounts = sorted(
            t.amount for t in PaymentTransaction.objects.filter(escrow=self.escrow, kind="payout")
        )
        # rider gets the fee, seller gets the remainder (no commission configured)
        self.assertEqual(amounts, [Decimal("5000.00"), Decimal("95000.00")])
