#!/usr/bin/env python3
"""
Broaden market data to cover BOTH crops and livestock.

  * Adds a `category` field to MarketPrice (crop / livestock / input).
  * Adds a ?category= filter to the MarketPrice API.
  * Rewrites the seed command: 37 commodities across grains, cash crops,
    fruit & veg, AND livestock products (meat, milk, eggs, honey, fish, live
    animals, hides) — each with the correct unit and a realistic price.

Run from the directory containing manage.py:
    python market_breadth.py
Then:
    python manage.py makemigrations marketprices
    python manage.py migrate
    python manage.py seed_market_prices
"""
import os
import sys
import shutil
from datetime import datetime

BACKUP = ".backend_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S")

# ---- model edit: add CATEGORY_CHOICES + category field ---------------------
MODEL_CHOICES_OLD = '''    PRICE_TYPE_CHOICES = [
        ("local", "Local"),
        ("regional", "Regional"),
        ("export", "Export"),
    ]'''
MODEL_CHOICES_NEW = '''    PRICE_TYPE_CHOICES = [
        ("local", "Local"),
        ("regional", "Regional"),
        ("export", "Export"),
    ]

    CATEGORY_CHOICES = [
        ("crop", "Crop"),
        ("livestock", "Livestock"),
        ("input", "Input"),
    ]'''

MODEL_FIELD_OLD = '''    price_type = models.CharField(
        max_length=20, choices=PRICE_TYPE_CHOICES, default="local"
    )
    price = models.DecimalField(max_digits=12, decimal_places=2)'''
MODEL_FIELD_NEW = '''    price_type = models.CharField(
        max_length=20, choices=PRICE_TYPE_CHOICES, default="local"
    )
    category = models.CharField(
        max_length=20, choices=CATEGORY_CHOICES, default="crop"
    )
    price = models.DecimalField(max_digits=12, decimal_places=2)'''

# ---- viewset edit: add ?category= filter -----------------------------------
VIEW_OLD = '''        commodity = self.request.query_params.get("commodity")
        country = self.request.query_params.get("country")
        price_type = self.request.query_params.get("price_type")
        if commodity:
            qs = qs.filter(commodity__iexact=commodity)
        if country:
            qs = qs.filter(country__iexact=country)
        if price_type:
            qs = qs.filter(price_type=price_type)
        return qs'''
VIEW_NEW = '''        commodity = self.request.query_params.get("commodity")
        country = self.request.query_params.get("country")
        price_type = self.request.query_params.get("price_type")
        category = self.request.query_params.get("category")
        if commodity:
            qs = qs.filter(commodity__iexact=commodity)
        if country:
            qs = qs.filter(country__iexact=country)
        if price_type:
            qs = qs.filter(price_type=price_type)
        if category:
            qs = qs.filter(category__iexact=category)
        return qs'''

# ---- new seed command ------------------------------------------------------
SEED = '''from datetime import date, timedelta
from decimal import Decimal
import random

from django.core.management.base import BaseCommand
from marketprices.models import MarketPrice

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
    help = "Seed sample crop + livestock MarketPrice rows for the AI assistant (idempotent)."

    def handle(self, *args, **options):
        random.seed(42)  # deterministic -> re-runs are idempotent
        today = date.today()
        dates = [today - timedelta(days=d) for d in (10, 5, 0)]  # mini trend

        created = updated = 0
        for commodity, variety, category, unit, base in COMMODITIES:
            for country, region in COUNTRIES[: random.randint(2, 3)]:
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
                                "category": category,
                                "region": region,
                                "price": price,
                                "currency": "USD",
                                "unit": unit,
                                "source": "Seed data (sample)",
                            },
                        )
                        created += int(was_created)
                        updated += int(not was_created)

        crops = sum(1 for c in COMMODITIES if c[2] == "crop")
        stock = sum(1 for c in COMMODITIES if c[2] == "livestock")
        self.stdout.write(self.style.SUCCESS(
            f"Seeded {len(COMMODITIES)} commodities ({crops} crop, {stock} livestock): "
            f"{created} created, {updated} updated. Total rows now: {MarketPrice.objects.count()}"
        ))
'''


def main():
    if not os.path.exists("manage.py"):
        sys.exit("ERROR: run from the directory containing manage.py (agricore_project/).")

    model_p = "marketprices/models.py"
    view_p = "marketprices/api/views.py"
    seed_p = "marketprices/management/commands/seed_market_prices.py"
    for p in (model_p, view_p, seed_p):
        if not os.path.exists(p):
            sys.exit(f"ERROR: missing {p}")

    with open(model_p, encoding="utf-8") as f:
        m = f.read()
    with open(view_p, encoding="utf-8") as f:
        v = f.read()

    problems = []
    if "category" in m and "CATEGORY_CHOICES" in m:
        problems.append("models.py already has category")
    if m.count(MODEL_CHOICES_OLD) != 1:
        problems.append("models.py PRICE_TYPE_CHOICES anchor not found once")
    if m.count(MODEL_FIELD_OLD) != 1:
        problems.append("models.py price_type field anchor not found once")
    if v.count(VIEW_OLD) != 1:
        problems.append("views.py get_queryset anchor not found once")
    if problems:
        print("Aborting - code didn't match expected:")
        for p in problems:
            print("  -", p)
        sys.exit(1)

    os.makedirs(BACKUP, exist_ok=True)
    for p in (model_p, view_p, seed_p):
        dest = os.path.join(BACKUP, p)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy2(p, dest)

    m = m.replace(MODEL_CHOICES_OLD, MODEL_CHOICES_NEW, 1)
    m = m.replace(MODEL_FIELD_OLD, MODEL_FIELD_NEW, 1)
    with open(model_p, "w", encoding="utf-8") as f:
        f.write(m)
    print("  [edit] marketprices/models.py (category field)")

    v = v.replace(VIEW_OLD, VIEW_NEW, 1)
    with open(view_p, "w", encoding="utf-8") as f:
        f.write(v)
    print("  [edit] marketprices/api/views.py (?category= filter)")

    with open(seed_p, "w", encoding="utf-8") as f:
        f.write(SEED)
    print("  [edit] seed_market_prices.py (37 commodities: crops + livestock)")

    print(f"\nDone. Backups in {BACKUP}/")
    print("Next:\n  python manage.py makemigrations marketprices\n  python manage.py migrate\n  python manage.py seed_market_prices")


if __name__ == "__main__":
    main()
