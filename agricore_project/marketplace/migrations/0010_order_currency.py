# Adds a settlement currency to Order so escrow/payment amounts are exact.

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("marketplace", "0009_product_is_published"),
    ]

    operations = [
        migrations.AddField(
            model_name="order",
            name="currency",
            field=models.CharField(default="UGX", max_length=3),
        ),
    ]
