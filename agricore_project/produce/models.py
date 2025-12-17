# produce/models.py
from django.db import models
from farms.models import Farm

class ProduceCollection(models.Model):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='produce_collections')
    source = models.CharField(
        max_length=20,
        choices=[('crop', 'Crop Harvest'), ('animal', 'Animal Product')],
    )
    product_name = models.CharField(max_length=255)
    quantity = models.DecimalField(max_digits=12, decimal_places=2)
    unit = models.CharField(
        max_length=20,
        choices=[
            ('kg', 'Kilograms (kg)'),
            ('liters', 'Liters'),
            ('crates', 'Crates'),
            ('bags', 'Bags (90kg)'),
            ('tons', 'Tons'),
            ('pieces', 'Pieces'),
        ],
        default='kg'
    )
    collection_date = models.DateField()
    quality_grade = models.CharField(max_length=100, blank=True, null=True)
    notes = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-collection_date', '-created_at']
        verbose_name = 'Produce Collection'
        verbose_name_plural = 'Produce Collections'

    def __str__(self):
        return f"{self.quantity} {self.unit} of {self.product_name} ({self.get_source_display()}) - {self.collection_date}"