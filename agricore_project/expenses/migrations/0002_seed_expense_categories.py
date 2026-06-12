from django.db import migrations

CATEGORIES = [
    ("input", "Seeds, fertilizer, feed, agro-chemicals"),
    ("labor", "Wages and labor costs"),
    ("equipment", "Equipment purchase and maintenance"),
    ("utilities", "Water, power, fuel"),
    ("overhead", "Miscellaneous and overhead"),
]


def seed(apps, schema_editor):
    ExpenseCategory = apps.get_model("expenses", "ExpenseCategory")
    for name, desc in CATEGORIES:
        ExpenseCategory.objects.get_or_create(name=name, defaults={"description": desc})


def unseed(apps, schema_editor):
    ExpenseCategory = apps.get_model("expenses", "ExpenseCategory")
    ExpenseCategory.objects.filter(name__in=[c[0] for c in CATEGORIES]).delete()


class Migration(migrations.Migration):
    dependencies = [("expenses", "0001_initial")]
    operations = [migrations.RunPython(seed, unseed)]
