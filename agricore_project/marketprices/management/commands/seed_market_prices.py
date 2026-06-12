from datetime import date, timedelta
from decimal import Decimal
import random

from django.core.management.base import BaseCommand
from marketprices.models import MarketPrice

# (commodity, variety, unit, base price in USD per unit)
COMMODITIES = [
    ("Maize", "", "ton", 300),
    ("Coffee", "Arabica", "ton", 4200),
    ("Coffee", "Robusta", "ton", 2500),
    ("Beans", "", "ton", 850),
    ("Rice", "", "ton", 600),
    ("Tomatoes", "", "ton", 450),
    ("Cassava", "", "ton", 230),
    ("Sorghum", "", "ton", 320),
    ("Groundnuts", "", "ton", 1100),
    ("Bananas", "", "ton", 380),
    ("Tea", "", "ton", 2600),
    ("Cocoa", "", "ton", 7800),
    ("Sesame", "", "ton", 1700),
]

COUNTRIES = [
    ("Uganda", "Kampala"),
    ("Kenya", "Nairobi"),
    ("Tanzania", "Dar es Salaam"),
    ("Rwanda", "Kigali"),
    ("Nigeria", "Lagos"),
]

PRICE_TYPES = ["local", "regional", "export"]
TYPE_MULT = {"local": 1.0, "regional": 1.08, "export": 1.20}


class Command(BaseCommand):
    help = "Seed sample MarketPrice rows for the data-aware AI assistant (idempotent)."

    def handle(self, *args, **options):
        random.seed(42)  # deterministic -> re-runs are idempotent
        today = date.today()
        dates = [today - timedelta(days=d) for d in (10, 5, 0)]  # mini trend

        created = updated = 0
        for commodity, variety, unit, base in COMMODITIES:
            for country, region in COUNTRIES[: random.randint(2, 4)]:
                for d in dates:
                    for ptype in PRICE_TYPES:
                        drift = 1 + random.uniform(-0.06, 0.10)
                        price = Decimal(str(round(base * TYPE_MULT[ptype] * drift, 2)))
                        _, was_created = MarketPrice.objects.update_or_create(
                            commodity=commodity,
                            variety=variety,
                            country=country,
                            price_type=ptype,
                            recorded_on=d,
                            defaults={
                                "region": region,
                                "price": price,
                                "currency": "USD",
                                "unit": unit,
                                "source": "Seed data (sample)",
                            },
                        )
                        created += int(was_created)
                        updated += int(not was_created)

        self.stdout.write(self.style.SUCCESS(
            f"Market prices seeded: {created} created, {updated} updated. "
            f"Total rows now: {MarketPrice.objects.count()}"
        ))
