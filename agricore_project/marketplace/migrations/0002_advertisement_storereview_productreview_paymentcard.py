# Generated migration for new marketplace models

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('marketplace', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='Advertisement',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('title', models.CharField(max_length=255)),
                ('description', models.TextField(blank=True)),
                ('image', models.ImageField(blank=True, null=True, upload_to='advertisements/')),
                ('background_color', models.CharField(default='#10b981', max_length=7)),
                ('text_color', models.CharField(default='#ffffff', max_length=7)),
                ('cta_text', models.CharField(default='Shop Now', max_length=100)),
                ('link_url', models.URLField(blank=True)),
                ('font_family', models.CharField(default='Inter, sans-serif', max_length=100)),
                ('title_font_size', models.IntegerField(default=30)),
                ('description_font_size', models.IntegerField(default=18)),
                ('image_fit', models.CharField(default='cover', max_length=20)),
                ('image_position', models.CharField(default='center', max_length=20)),
                ('image_brightness', models.IntegerField(default=100)),
                ('audio', models.FileField(blank=True, null=True, upload_to='advertisements/audio/')),
                ('duration_days', models.IntegerField(default=1)),
                ('price_paid', models.DecimalField(decimal_places=2, default=0, max_digits=10)),
                ('is_active', models.BooleanField(default=True)),
                ('start_date', models.DateTimeField(auto_now_add=True)),
                ('end_date', models.DateTimeField(blank=True, null=True)),
                ('impressions', models.IntegerField(default=0)),
                ('clicks', models.IntegerField(default=0)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('store', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='advertisements', to='marketplace.store')),
            ],
        ),
        migrations.CreateModel(
            name='StoreReview',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('rating', models.IntegerField(default=5)),
                ('comment', models.TextField(blank=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('store', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='store_reviews', to='marketplace.store')),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'unique_together': {('store', 'user')},
            },
        ),
        migrations.CreateModel(
            name='ProductReview',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('rating', models.IntegerField(default=5)),
                ('comment', models.TextField(blank=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('product', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='product_reviews', to='marketplace.product')),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'unique_together': {('product', 'user')},
            },
        ),
        migrations.CreateModel(
            name='PaymentCard',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('cardholder_name', models.CharField(max_length=255)),
                ('card_number_last4', models.CharField(max_length=4)),
                ('card_brand', models.CharField(blank=True, max_length=50)),
                ('expiry_month', models.IntegerField()),
                ('expiry_year', models.IntegerField()),
                ('is_default', models.BooleanField(default=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='payment_cards', to=settings.AUTH_USER_MODEL)),
            ],
        ),
    ]
