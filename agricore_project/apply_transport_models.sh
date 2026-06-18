#!/usr/bin/env bash
# Transporter subsystem -- Patcher 1 of 3: data foundation.
# Adds the `transporter` role and Transporter / DeliveryJob / TransporterReview
# models (self-contained, appended to logistics). After running: makemigrations
# + migrate.
set -uo pipefail
if [ ! -f accounts/models.py ] || [ ! -f logistics/models.py ] || [ ! -f manage.py ]; then
  echo "X Run from the Django project root (needs accounts/models.py, logistics/models.py, manage.py)."; exit 1
fi
BK="transport_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
cp -a accounts/models.py "$BK/accounts_models.py"
cp -a logistics/models.py "$BK/logistics_models.py"
echo ">> Backup: $BK/"
cat > .tm.py << 'TMW_EOF'
import sys, ast
def parse_or_die(p):
    try: ast.parse(open(p,encoding='utf-8').read())
    except SyntaxError as e: print('   X %s invalid: %s'%(p,e)); sys.exit(1)

# 1) accounts: add the transporter role choice
AP='accounts/models.py'; a=open(AP,encoding='utf-8').read()
if "('transporter', 'Transporter')" not in a:
    OLD='''        ('specialized', 'Specialized Professional'),
    ]'''
    NEW='''        ('specialized', 'Specialized Professional'),
        ('transporter', 'Transporter'),
    ]'''
    if OLD not in a: print('   X accounts ROLE_CHOICES anchor not found'); sys.exit(1)
    open(AP,'w',encoding='utf-8').write(a.replace(OLD,NEW,1)); parse_or_die(AP)
    print('   OK accounts/models.py: transporter role added')
else: print('   - accounts already has transporter role')

# 2) logistics: append the self-contained transporter subsystem
LP='logistics/models.py'; l=open(LP,encoding='utf-8').read()
if 'class Transporter(' not in l:
    BLOCK='''

# ===== Verified Trade Chain: transporter subsystem (self-contained) =====
from django.db import models
from accounts.models import CustomUser
from marketplace.models import Order
from escrow.models import Escrow


class Transporter(models.Model):
    """A registered rider/driver who delivers orders (boda, pickup, truck, taxi)."""
    VEHICLE_CHOICES = [
        ("boda", "Boda boda (motorcycle)"),
        ("pickup", "Pickup"),
        ("truck", "Truck"),
        ("taxi", "Taxi / van"),
        ("bicycle", "Bicycle"),
    ]
    user = models.OneToOneField(CustomUser, on_delete=models.CASCADE, related_name="transporter")
    vehicle_type = models.CharField(max_length=20, choices=VEHICLE_CHOICES, default="boda")
    vehicle_plate = models.CharField(max_length=30, blank=True, default="")
    national_id = models.CharField(max_length=40, blank=True, default="")
    phone = models.CharField(max_length=32, blank=True, default="")
    service_area = models.CharField(max_length=160, blank=True, default="", help_text="Districts/areas served")
    is_verified = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    rating_avg = models.DecimalField(max_digits=3, decimal_places=2, default=0)
    rating_count = models.PositiveIntegerField(default=0)
    deposit_required = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    deposit_balance = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    photo = models.ImageField(upload_to="transporters/", blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Transporter {self.user} ({self.vehicle_type})"


class DeliveryJob(models.Model):
    """A delivery assignment for an order, carried by a transporter."""
    STATUS_CHOICES = [
        ("open", "Open (awaiting a rider)"),
        ("accepted", "Accepted"),
        ("picked_up", "Picked up"),
        ("delivered", "Delivered"),
        ("cancelled", "Cancelled"),
    ]
    order = models.OneToOneField(Order, on_delete=models.CASCADE, related_name="delivery_job")
    escrow = models.ForeignKey(Escrow, on_delete=models.SET_NULL, null=True, blank=True, related_name="delivery_jobs")
    created_by = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name="created_delivery_jobs")
    transporter = models.ForeignKey(Transporter, on_delete=models.SET_NULL, null=True, blank=True, related_name="jobs")
    vehicle_type_required = models.CharField(max_length=20, blank=True, default="")
    pickup_location = models.CharField(max_length=255, blank=True, default="")
    drop_location = models.CharField(max_length=255, blank=True, default="")
    offered_fee = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    currency = models.CharField(max_length=3, default="UGX")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="open")
    pickup_code = models.CharField(max_length=8, blank=True, default="")
    notes = models.TextField(blank=True, default="")
    accepted_at = models.DateTimeField(blank=True, null=True)
    picked_up_at = models.DateTimeField(blank=True, null=True)
    delivered_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"DeliveryJob #{self.pk} order={self.order_id} ({self.status})"


class TransporterReview(models.Model):
    transporter = models.ForeignKey(Transporter, on_delete=models.CASCADE, related_name="reviews")
    order = models.ForeignKey(Order, on_delete=models.SET_NULL, null=True, blank=True)
    by_user = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name="transporter_reviews")
    rating = models.PositiveSmallIntegerField(default=5)
    comment = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Review {self.rating}* for {self.transporter_id}"
'''
    open(LP,'w',encoding='utf-8').write(l + BLOCK); parse_or_die(LP)
    print('   OK logistics/models.py: Transporter + DeliveryJob + TransporterReview appended')
else: print('   - logistics already has transporter models')
print('DONE')
TMW_EOF
python3 .tm.py; RC=$?
rm -f .tm.py
if [ $RC -ne 0 ]; then
  echo "X failed; restoring."
  cp -a "$BK/accounts_models.py" accounts/models.py
  cp -a "$BK/logistics_models.py" logistics/models.py
  exit 1
fi
echo ""
echo ">> Code applied. Create + apply migrations:"
echo "     python manage.py makemigrations accounts logistics && python manage.py migrate && python manage.py check"
echo "   then restart. (This is Patcher 1 of 3 -- endpoints + UI follow.)"
echo ">> Rollback: cp -a $BK/accounts_models.py accounts/models.py && cp -a $BK/logistics_models.py logistics/models.py"
