"""Register an IPN URL with Pesapal once, then print the ipn_id to copy into
PESAPAL_IPN_ID in .env.

Usage:
    python manage.py register_pesapal_ipn https://abc123.ngrok-free.app/payments/ipn/

If you omit the URL, it builds one from PESAPAL_BASE_PUBLIC_URL + /payments/ipn/.
"""
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from payments.services import pesapal


class Command(BaseCommand):
    help = "Register an IPN URL with Pesapal and print the resulting ipn_id."

    def add_arguments(self, parser):
        parser.add_argument(
            "ipn_url",
            nargs="?",
            help="Public HTTPS URL to your IPN endpoint, e.g. https://<host>/payments/ipn/",
        )

    def handle(self, *args, **options):
        ipn_url = options.get("ipn_url")
        if not ipn_url:
            base = (getattr(settings, "PESAPAL_BASE_PUBLIC_URL", "") or "").rstrip("/")
            if not base:
                raise CommandError(
                    "Pass an IPN URL, or set PESAPAL_BASE_PUBLIC_URL in .env."
                )
            ipn_url = f"{base}/payments/ipn/"

        env = getattr(settings, "PESAPAL_ENV", "sandbox")
        self.stdout.write(f"Registering IPN ({env}): {ipn_url}")
        try:
            token = pesapal.get_access_token()
            ipn_id = pesapal.register_ipn(token, ipn_url)
        except pesapal.PesapalError as e:
            raise CommandError(f"Pesapal error: {e}")

        self.stdout.write(self.style.SUCCESS(f"ipn_id = {ipn_id}"))
        self.stdout.write("Copy this into .env as:")
        self.stdout.write(f"  PESAPAL_IPN_ID={ipn_id}")
        self.stdout.write("Then restart the server so the new value loads.")
