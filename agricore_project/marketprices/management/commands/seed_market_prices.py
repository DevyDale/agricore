from datetime import date, timedelta
from decimal import Decimal
import random

from django.core.management.base import BaseCommand
from django.db import transaction
from marketprices.models import MarketPrice

SEED_TAG = "Seed data (sample)"

# (commodity, variety, category, unit, base price in USD per unit)
COMMODITIES = [
    # --- crops: grains & staples ---
    ("Maize", "", "crop", "ton", 300),
    ("Rice", "", "crop", "ton", 600),
    ("Sorghum", "", "crop", "ton", 320),
    ("Millet", "", "crop", "ton", 340),
    ("Wheat", "", "crop", "ton", 380),
    ("Beans", "", "crop", "ton", 850),
    ("Soybeans", "", "crop", "ton", 560),
    ("Groundnuts", "", "crop", "ton", 1100),
    ("Cassava", "", "crop", "ton", 230),
    ("Irish Potato", "", "crop", "ton", 400),
    ("Sweet Potato", "", "crop", "ton", 280),
    # --- crops: cash crops ---
    ("Coffee", "Arabica", "crop", "ton", 4200),
    ("Coffee", "Robusta", "crop", "ton", 2500),
    ("Tea", "", "crop", "ton", 2600),
    ("Cocoa", "", "crop", "ton", 7800),
    ("Cotton", "", "crop", "ton", 1800),
    ("Sesame", "", "crop", "ton", 1700),
    ("Sunflower", "", "crop", "ton", 700),
    # --- crops: fruit & veg ---
    ("Tomatoes", "", "crop", "ton", 450),
    ("Onions", "", "crop", "ton", 500),
    ("Bananas", "", "crop", "ton", 380),
    ("Mangoes", "", "crop", "ton", 550),
    ("Avocado", "", "crop", "ton", 900),
    ("Cabbage", "", "crop", "ton", 260),
    ("Pineapple", "", "crop", "ton", 420),
    # --- livestock & animal products ---
    ("Beef", "", "livestock", "kg", 4.5),
    ("Goat meat", "", "livestock", "kg", 6.0),
    ("Mutton", "", "livestock", "kg", 6.5),
    ("Pork", "", "livestock", "kg", 3.8),
    ("Chicken (broiler)", "", "livestock", "kg", 3.0),
    ("Eggs", "", "livestock", "tray", 3.5),
    ("Milk", "", "livestock", "liter", 0.6),
    ("Honey", "", "livestock", "kg", 8.0),
    ("Tilapia (fish)", "", "livestock", "kg", 3.2),
    ("Live cattle", "", "livestock", "head", 600),
    ("Live goat", "", "livestock", "head", 70),
    ("Hides & skins", "", "livestock", "kg", 1.5),
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
    help = "Seed sample crop + livestock MarketPrice rows (fast bulk insert, idempotent)."

    def handle(self, *args, **options):
        random.seed(42)  # deterministic
        today = date.today()
        dates = [today - timedelta(days=d) for d in (10, 5, 0)]

        objs = []
        for commodity, variety, category, unit, base in COMMODITIES:
            for country, region in COUNTRIES[: random.randint(2, 3)]:
                for d in dates:
                    for ptype in PRICE_TYPES:
                        drift = 1 + random.uniform(-0.06, 0.10)
                        price = Decimal(str(round(base * TYPE_MULT[ptype] * drift, 2)))
                        objs.append(MarketPrice(
                            commodity=commodity,
                            variety=variety,
                            category=category,
                            country=country,
                            region=region,
                            price_type=ptype,
                            price=price,
                            currency="USD",
                            unit=unit,
                            source=SEED_TAG,
                            recorded_on=d,
                        ))

        with transaction.atomic():
            deleted, _ = MarketPrice.objects.filter(source=SEED_TAG).delete()
            MarketPrice.objects.bulk_create(objs, batch_size=500)

        crops = sum(1 for c in COMMODITIES if c[2] == "crop")
        stock = sum(1 for c in COMMODITIES if c[2] == "livestock")
        self.stdout.write(self.style.SUCCESS(
            f"Seeded {len(COMMODITIES)} commodities ({crops} crop, {stock} livestock): "
            f"removed {deleted} old, inserted {len(objs)}. "
            f"Total rows now: {MarketPrice.objects.count()}"
        ))
