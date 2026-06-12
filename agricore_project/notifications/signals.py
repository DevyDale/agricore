"""Auto-create notifications on key platform events."""
from django.db.models.signals import post_save, pre_save
from django.dispatch import receiver

from .services import notify

# --- Marketplace: new order ---------------------------------------------------
try:
    from marketplace.models import Order
except Exception:
    Order = None

if Order is not None:
    @receiver(post_save, sender=Order)
    def _order_created(sender, instance, created, **kwargs):
        if not created:
            return
        try:
            seller = getattr(getattr(instance, "store", None), "owner", None)
            notify(seller, "New order received",
                   f"You have a new order (#{instance.pk}).",
                   category="order", related_table="order", related_id=instance.pk)
            notify(getattr(instance, "buyer", None), "Order placed",
                   f"Your order #{instance.pk} has been placed.",
                   category="order", related_table="order", related_id=instance.pk)
        except Exception:
            pass

# --- Communications: new message ---------------------------------------------
try:
    from communications.models import Message, ConversationParticipant
except Exception:
    Message = None
    ConversationParticipant = None

if Message is not None and ConversationParticipant is not None:
    @receiver(post_save, sender=Message)
    def _message_created(sender, instance, created, **kwargs):
        if not created:
            return
        try:
            text = getattr(instance, "content", "") or ""
            preview = (text[:60] + "\u2026") if len(text) > 60 else text
            others = ConversationParticipant.objects.filter(
                conversation_id=instance.conversation_id
            ).exclude(user_id=instance.sender_id).select_related("user")
            for p in others:
                notify(p.user, "New message", preview,
                       category="message", related_table="conversation",
                       related_id=instance.conversation_id)
        except Exception:
            pass

# --- Escrow: status transitions ----------------------------------------------
try:
    from escrow.models import Escrow
except Exception:
    Escrow = None

if Escrow is not None:
    @receiver(pre_save, sender=Escrow)
    def _capture_old_escrow_status(sender, instance, **kwargs):
        if instance.pk:
            try:
                instance._old_status = sender.objects.get(pk=instance.pk).status
            except sender.DoesNotExist:
                instance._old_status = None
        else:
            instance._old_status = None

    @receiver(post_save, sender=Escrow)
    def _escrow_status_changed(sender, instance, created, **kwargs):
        old = getattr(instance, "_old_status", None)
        if created or old == instance.status:
            return
        try:
            buyer = instance.buyer
            seller = getattr(getattr(instance.order, "store", None), "owner", None)
            if instance.status == "held":
                notify(buyer, "Payment secured",
                       f"Your payment for order #{instance.order_id} is now held in escrow.",
                       category="escrow", related_table="escrow", related_id=instance.pk)
                notify(seller, "Order funded",
                       "An order is funded and awaiting fulfilment.",
                       category="escrow", related_table="escrow", related_id=instance.pk)
            elif instance.status == "released":
                notify(seller, "Payout released",
                       f"Funds for order #{instance.order_id} have been released to you.",
                       category="payment", related_table="escrow", related_id=instance.pk)
                notify(buyer, "Order completed",
                       f"You released the funds for order #{instance.order_id}.",
                       category="escrow", related_table="escrow", related_id=instance.pk)
            elif instance.status == "refunded":
                notify(buyer, "Refund issued",
                       f"Your payment for order #{instance.order_id} was refunded.",
                       category="payment", related_table="escrow", related_id=instance.pk)
        except Exception:
            pass
