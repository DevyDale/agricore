"""Create a small UGX test order for a live Pesapal round-trip and print the
start URL to open in the browser.

Usage:
    python manage.py pesapal_test_order --user <username-or-email> --amount 500
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError

from marketplace.models import Order, Store

User = get_user_model()


class Command(BaseCommand):
    help = "Create a small live-test order and print its /payments/start/ URL."

    def add_arguments(self, parser):
        parser.add_argument("--user", help="Buyer username or email (defaults to first superuser).")
        parser.add_argument("--amount", default="500", help="Amount (default 500).")
        parser.add_argument("--currency", default="UGX", help="Currency (default UGX).")

    def handle(self, *args, **opts):
        ident = opts.get("user")
        if ident:
            user = User.objects.filter(username=ident).first() or User.objects.filter(email=ident).first()
            if not user:
                raise CommandError(f"No user matching '{ident}'.")
        else:
            user = User.objects.filter(is_superuser=True).first() or User.objects.first()
            if not user:
                raise CommandError("No users exist; create one first.")

        store = (
            Store.objects.filter(owner=user).first()
            or Store.objects.first()
            or Store.objects.create(owner=user, name="Pesapal Test Stall")
        )

        order = Order.objects.create(
            buyer=user,
            store=store,
            total_amount=Decimal(str(opts["amount"])),
            currency=opts["currency"],
            status="pending",
            shipping_address="PESAPAL LIVE TEST",
        )

        self.stdout.write(self.style.SUCCESS(f"Created test order #{order.id}"))
        self.stdout.write(f"  buyer    : {user.username} ({user.email})")
        self.stdout.write(f"  amount   : {order.currency} {order.total_amount}")
        self.stdout.write(f"  store    : {store.name} (#{store.id})")
        self.stdout.write("")
        self.stdout.write("Log in to a browser session as that buyer, then open:")
        self.stdout.write(self.style.HTTP_INFO(f"  /payments/start/{order.id}/"))
