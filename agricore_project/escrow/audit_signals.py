"""Security audit trail for money movement.

Writes an AuditLog row for every escrow state change, payment-transaction event
and payout-account change, so there is an immutable record of who/what moved
money. Auditing must never break a money operation, so every write is guarded.
"""
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.contrib.contenttypes.models import ContentType
from django.contrib.auth import get_user_model

from utils.models import AuditLog
from escrow.models import Escrow, PaymentTransaction, PayoutAccount


def _log(instance, action, user=None, changes=None):
    try:
        AuditLog.objects.create(
            user=user if isinstance(user, get_user_model()) else None,
            content_type=ContentType.objects.get_for_model(instance.__class__),
            object_id=instance.pk,
            action=str(action)[:50],
            changes=changes or {},
        )
    except Exception:
        # Never let auditing interfere with the underlying money operation.
        pass


@receiver(post_save, sender=Escrow)
def audit_escrow(sender, instance, created, **kwargs):
    status = getattr(instance, "status", "")
    action = "escrow_created" if created else "escrow_%s" % status
    _log(
        instance,
        action,
        user=getattr(instance, "buyer", None),
        changes={
            "status": status,
            "amount": str(getattr(instance, "amount", "")),
            "currency": getattr(instance, "currency", ""),
            "order_id": getattr(instance, "order_id", None),
        },
    )


@receiver(post_save, sender=PaymentTransaction)
def audit_payment_txn(sender, instance, created, **kwargs):
    _log(
        instance,
        "payment_%s_%s" % (getattr(instance, "kind", ""), getattr(instance, "status", "")),
        changes={
            "kind": getattr(instance, "kind", ""),
            "status": getattr(instance, "status", ""),
            "amount": str(getattr(instance, "amount", "")),
            "fee": str(getattr(instance, "fee", "")),
            "currency": getattr(instance, "currency", ""),
            "tx_ref": getattr(instance, "tx_ref", ""),
            "escrow_id": getattr(instance, "escrow_id", None),
        },
    )


@receiver(post_save, sender=PayoutAccount)
def audit_payout_account(sender, instance, created, **kwargs):
    number = getattr(instance, "account_number", "") or ""
    _log(
        instance,
        "payout_account_created" if created else "payout_account_updated",
        user=getattr(instance, "user", None),
        changes={
            "method": getattr(instance, "method", ""),
            "account_name": getattr(instance, "account_name", ""),
            # Store only the last 4 digits — never the full account number.
            "account_last4": number[-4:],
        },
    )
