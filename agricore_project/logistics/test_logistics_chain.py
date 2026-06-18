"""Verified Trade Chain — logistics tests.

Covers the delivery-job lifecycle (create -> accept -> pickup), the app-less
rider link endpoints (view -> pickup -> deliver), and the pure USSD menu logic.
Run with:  python manage.py test logistics --keepdb
"""
from decimal import Decimal

from django.test import TestCase, SimpleTestCase
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

from marketplace.models import Store, Order
from escrow.models import Escrow
from logistics.models import Transporter, DeliveryJob
from logistics.api.views import _ussd_render

User = get_user_model()


def make_user(username, email):
    return User.objects.create_user(
        username=username, email=email, password="pw12345!", phone="0772000000"
    )


class DeliveryJobApiTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.buyer = make_user("lbuyer", "lbuyer@example.com")
        self.seller = make_user("lseller", "lseller@example.com")
        self.rider = make_user("lrider", "lrider@example.com")
        self.store = Store.objects.create(
            owner=self.seller, name="L Store",
            owner_name="L Seller", owner_phone="0772444444",
        )
        self.order = Order.objects.create(
            buyer=self.buyer, store=self.store,
            total_amount=Decimal("50000"), status="paid",
        )
        self.escrow = Escrow.objects.create(
            order=self.order, buyer=self.buyer,
            amount=Decimal("50000"), currency="UGX", status="held",
        )
        self.transporter = Transporter.objects.create(
            user=self.rider, vehicle_type="boda", phone="0772555555", is_verified=True,
        )

    def _create_job(self):
        self.client.force_authenticate(self.seller)
        r = self.client.post(
            "/api/delivery-jobs/",
            {"order": self.order.id, "drop_location": "Nakawa", "offered_fee": "5000"},
            format="json",
        )
        self.assertEqual(r.status_code, 201, r.content)
        return DeliveryJob.objects.get(id=r.data["id"])

    def test_seller_creates_job_and_rider_accepts(self):
        job = self._create_job()
        self.client.force_authenticate(self.rider)
        r = self.client.post(f"/api/delivery-jobs/{job.id}/accept/", {}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        job.refresh_from_db()
        self.assertEqual(job.status, "accepted")
        self.assertEqual(job.transporter_id, self.transporter.id)

    def test_pickup_requires_correct_code_and_issues_buyer_code(self):
        job = self._create_job()
        self.client.force_authenticate(self.rider)
        self.client.post(f"/api/delivery-jobs/{job.id}/accept/", {}, format="json")

        wrong = self.client.post(
            f"/api/delivery-jobs/{job.id}/pickup/", {"pickup_code": "000000"}, format="json"
        )
        self.assertEqual(wrong.status_code, 400, wrong.content)

        job.refresh_from_db()
        right = self.client.post(
            f"/api/delivery-jobs/{job.id}/pickup/", {"pickup_code": job.pickup_code}, format="json"
        )
        self.assertEqual(right.status_code, 200, right.content)
        job.refresh_from_db()
        self.escrow.refresh_from_db()
        self.assertEqual(job.status, "picked_up")
        self.assertTrue(self.escrow.delivery_otp)  # buyer's delivery code issued at pickup


class RiderLinkTests(TestCase):
    def setUp(self):
        self.buyer = make_user("tbuyer", "tbuyer@example.com")
        self.seller = make_user("tseller", "tseller@example.com")
        self.store = Store.objects.create(
            owner=self.seller, name="T Store",
            owner_name="T Seller", owner_phone="0772666666",
        )
        self.order = Order.objects.create(
            buyer=self.buyer, store=self.store,
            total_amount=Decimal("40000"), status="paid",
        )
        self.escrow = Escrow.objects.create(
            order=self.order, buyer=self.buyer,
            amount=Decimal("40000"), currency="UGX", status="held",
        )
        self.job = DeliveryJob.objects.create(
            order=self.order, escrow=self.escrow, created_by=self.seller,
            status="accepted", pickup_code="654321",
            access_token="testtoken123", access_phone="+256772777777", drop_location="Kira",
        )

    def test_link_pickup_then_deliver(self):
        c = APIClient()  # public, no auth — the token is the credential
        view = c.get(f"/api/rider-link/{self.job.access_token}/")
        self.assertEqual(view.status_code, 200, view.content)
        self.assertEqual(view.data["next_action"], "pickup")

        pick = c.post(
            f"/api/rider-link/{self.job.access_token}/pickup/",
            {"pickup_code": "654321"}, format="json",
        )
        self.assertEqual(pick.status_code, 200, pick.content)
        self.job.refresh_from_db()
        self.escrow.refresh_from_db()
        self.assertEqual(self.job.status, "picked_up")
        self.assertTrue(self.escrow.delivery_otp)

        deliver = c.post(
            f"/api/rider-link/{self.job.access_token}/deliver/",
            {"otp": self.escrow.delivery_otp}, format="json",
        )
        self.assertEqual(deliver.status_code, 200, deliver.content)
        self.job.refresh_from_db()
        self.escrow.refresh_from_db()
        self.order.refresh_from_db()
        self.assertEqual(self.job.status, "delivered")
        self.assertIsNotNone(self.escrow.delivered_confirmed_at)
        self.assertEqual(self.order.status, "delivered")

    def test_invalid_token_is_404(self):
        c = APIClient()
        r = c.get("/api/rider-link/not-a-real-token/")
        self.assertEqual(r.status_code, 404)

    def test_wrong_pickup_code_rejected(self):
        c = APIClient()
        r = c.post(
            f"/api/rider-link/{self.job.access_token}/pickup/",
            {"pickup_code": "111111"}, format="json",
        )
        self.assertEqual(r.status_code, 400, r.content)


class _FakeJob:
    def __init__(self, order_id, status, drop=""):
        self.order_id = order_id
        self.status = status
        self.drop_location = drop


class UssdRenderTests(SimpleTestCase):
    """Pure menu logic — no DB — exercised against simulated AT input chains."""

    def setUp(self):
        self.calls = []

        def pick(job, code):
            self.calls.append(("pickup", job.order_id, code))
            return True, "Picked up."

        def deliver(job, code):
            self.calls.append(("deliver", job.order_id, code))
            return True, "Delivered."

        self.pick = pick
        self.deliver = deliver

    def test_no_jobs(self):
        out = _ussd_render("", [], self.pick, self.deliver)
        self.assertTrue(out.startswith("END You have no"))

    def test_single_job_prompt_then_pickup(self):
        job = _FakeJob(11, "accepted", "Nakawa")
        self.assertTrue(_ussd_render("", [job], self.pick, self.deliver).startswith("CON"))
        out = _ussd_render("123456", [job], self.pick, self.deliver)
        self.assertTrue(out.startswith("END"))
        self.assertEqual(self.calls[-1], ("pickup", 11, "123456"))

    def test_multi_job_select_then_deliver(self):
        jobs = [_FakeJob(21, "accepted"), _FakeJob(22, "picked_up")]
        listing = _ussd_render("", jobs, self.pick, self.deliver)
        self.assertIn("Your deliveries", listing)
        _ussd_render("2*559900", jobs, self.pick, self.deliver)
        self.assertEqual(self.calls[-1], ("deliver", 22, "559900"))

    def test_invalid_selection(self):
        jobs = [_FakeJob(31, "accepted"), _FakeJob(32, "picked_up")]
        self.assertEqual(
            _ussd_render("9", jobs, self.pick, self.deliver), "END Invalid selection."
        )
