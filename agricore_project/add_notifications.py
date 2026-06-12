#!/usr/bin/env python
"""
add_notifications.py — scaffold a Notifications module and wire it in.

Creates a `notifications` app:
  - Notification model (per-user, categorized, read/unread)
  - REST API: list (+ ?unread=1), unread_count, read, read_all
  - services.notify(...) helper any app can call
  - real-time WebSocket push at ws/notifications/
  - auto-notifications on: new order, new message, escrow held/released/refunded

Then registers it in INSTALLED_APPS, urls.py (router), and asgi.py (websocket).
Run from the manage.py folder:

    python add_notifications.py
    python manage.py makemigrations notifications
    python manage.py migrate
    python manage.py check
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def resolve(name):
    direct = os.path.join(HERE, "agricore_project", name)
    if os.path.isfile(direct):
        return direct
    for root, dirs, files in os.walk(HERE):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        if os.path.basename(root) == "agricore_project" and name in files:
            return os.path.join(root, name)
    return direct


SETTINGS = resolve("settings.py")
URLS = resolve("urls.py")
ASGI = resolve("asgi.py")

APP = os.path.join(HERE, "notifications")

# ----------------------------- app files -----------------------------
FILES = {
    "__init__.py": "",
    "migrations/__init__.py": "",
    "api/__init__.py": "",
    "apps.py": '''from django.apps import AppConfig


class NotificationsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "notifications"

    def ready(self):
        import notifications.signals  # noqa: F401
''',
    "models.py": '''from django.conf import settings
from django.db import models


class Notification(models.Model):
    CATEGORY_CHOICES = [
        ("order", "Order"),
        ("payment", "Payment"),
        ("escrow", "Escrow"),
        ("task", "Task"),
        ("message", "Message"),
        ("logistics", "Logistics"),
        ("system", "System"),
    ]

    recipient = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications"
    )
    category = models.CharField(max_length=20, choices=CATEGORY_CHOICES, default="system")
    title = models.CharField(max_length=255)
    body = models.TextField(blank=True)
    related_table = models.CharField(max_length=50, blank=True)
    related_id = models.IntegerField(null=True, blank=True)
    url = models.CharField(max_length=500, blank=True)  # frontend deep link
    is_read = models.BooleanField(default=False)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["recipient", "is_read"])]

    def __str__(self):
        return f"[{self.category}] {self.title} -> {self.recipient_id}"
''',
    "admin.py": '''from django.contrib import admin
from .models import Notification


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("id", "recipient", "category", "title", "is_read", "created_at")
    list_filter = ("category", "is_read")
    search_fields = ("title", "body")
''',
    "services.py": '''"""Helper any app can import: `from notifications.services import notify`."""
from .models import Notification


def notify(recipient, title, body="", category="system",
           related_table="", related_id=None, url="", push=True):
    """Create a notification for `recipient` (a user) and optionally push it
    over the WebSocket. Safe to call from anywhere; returns the Notification."""
    if recipient is None:
        return None
    n = Notification.objects.create(
        recipient=recipient,
        title=title,
        body=body or "",
        category=category,
        related_table=related_table or "",
        related_id=related_id,
        url=url or "",
    )
    if push:
        _push(n)
    return n


def _push(notification):
    """Best-effort real-time push. Never raises into the caller."""
    try:
        from asgiref.sync import async_to_sync
        from channels.layers import get_channel_layer

        layer = get_channel_layer()
        if layer is None:
            return
        async_to_sync(layer.group_send)(
            f"notifications_{notification.recipient_id}",
            {
                "type": "notify.message",
                "data": {
                    "id": notification.id,
                    "category": notification.category,
                    "title": notification.title,
                    "body": notification.body,
                    "url": notification.url,
                    "created_at": notification.created_at.isoformat(),
                },
            },
        )
    except Exception:
        pass
''',
    "consumers.py": '''import json

from channels.generic.websocket import AsyncWebsocketConsumer


class NotificationConsumer(AsyncWebsocketConsumer):
    """Per-user live notifications. Connect to ws/notifications/?token=<JWT>."""

    async def connect(self):
        user = self.scope.get("user")
        if user is None or not getattr(user, "is_authenticated", False):
            await self.close()
            return
        self.group = f"notifications_{user.id}"
        await self.channel_layer.group_add(self.group, self.channel_name)
        await self.accept()

    async def disconnect(self, code):
        if hasattr(self, "group"):
            await self.channel_layer.group_discard(self.group, self.channel_name)

    async def notify_message(self, event):
        await self.send(text_data=json.dumps(event["data"]))
''',
    "routing.py": '''from django.urls import re_path

from .consumers import NotificationConsumer

websocket_urlpatterns = [
    re_path(r"ws/notifications/$", NotificationConsumer.as_asgi()),
]
''',
    "signals.py": '''"""Auto-create notifications on key platform events."""
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
            preview = (text[:60] + "\\u2026") if len(text) > 60 else text
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
''',
    "api/serializers.py": '''from rest_framework import serializers

from notifications.models import Notification


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = [
            "id", "category", "title", "body",
            "related_table", "related_id", "url",
            "is_read", "read_at", "created_at",
        ]
        read_only_fields = fields
''',
    "api/views.py": '''from django.utils import timezone
from rest_framework import mixins, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from notifications.models import Notification
from .serializers import NotificationSerializer


class NotificationViewSet(mixins.ListModelMixin,
                          mixins.RetrieveModelMixin,
                          viewsets.GenericViewSet):
    """A user's own notifications. Read-only list/detail + mark-read actions."""

    serializer_class = NotificationSerializer
    permission_classes = [IsAuthenticated]
    http_method_names = ["get", "post", "head", "options"]

    def get_queryset(self):
        qs = Notification.objects.filter(recipient=self.request.user)
        if self.request.query_params.get("unread") in ("1", "true", "True"):
            qs = qs.filter(is_read=False)
        return qs

    @action(detail=False, methods=["get"])
    def unread_count(self, request):
        count = Notification.objects.filter(recipient=request.user, is_read=False).count()
        return Response({"unread": count})

    @action(detail=True, methods=["post"])
    def read(self, request, pk=None):
        n = self.get_object()
        if not n.is_read:
            n.is_read = True
            n.read_at = timezone.now()
            n.save(update_fields=["is_read", "read_at"])
        return Response(self.get_serializer(n).data)

    @action(detail=False, methods=["post"])
    def read_all(self, request):
        updated = Notification.objects.filter(
            recipient=request.user, is_read=False
        ).update(is_read=True, read_at=timezone.now())
        return Response({"marked_read": updated})
''',
}

# ----------------------------- patches -----------------------------
PATCHES = [
    (SETTINGS,
     "    'expenses.apps.ExpensesConfig',",
     "    'expenses.apps.ExpensesConfig',\n    'notifications.apps.NotificationsConfig',",
     "notifications.apps.NotificationsConfig"),
    (URLS,
     "from escrow.api.views import EscrowViewSet, FlutterwaveWebhookView, PayoutAccountViewSet",
     "from escrow.api.views import EscrowViewSet, FlutterwaveWebhookView, PayoutAccountViewSet\nfrom notifications.api.views import NotificationViewSet",
     "from notifications.api.views import NotificationViewSet"),
    (URLS,
     "router.register(r'users', CustomUserViewSet, basename='user')",
     "router.register(r'users', CustomUserViewSet, basename='user')\nrouter.register(r'notifications', NotificationViewSet, basename='notification')",
     "basename='notification'"),
    (ASGI,
     "from communications.routing import websocket_urlpatterns",
     "from communications.routing import websocket_urlpatterns\nfrom notifications.routing import websocket_urlpatterns as notification_ws_urlpatterns",
     "notification_ws_urlpatterns"),
    (ASGI,
     "URLRouter(websocket_urlpatterns)",
     "URLRouter(websocket_urlpatterns + notification_ws_urlpatterns)",
     "websocket_urlpatterns + notification_ws_urlpatterns"),
]


def main():
    for p in (SETTINGS, URLS, ASGI):
        if not os.path.isfile(p):
            print(f"[ABORT] not found: {p}\nRun from the manage.py folder.")
            sys.exit(1)

    # validate patches first (don't write app files if a patch can't apply)
    planned = {}
    problems = []
    for path in {pp[0] for pp in PATCHES}:
        planned[path] = open(path, encoding="utf-8").read()
    for path, old, new, marker in PATCHES:
        text = planned[path]
        if marker in text:
            continue
        if text.count(old) != 1:
            problems.append(f"{os.path.relpath(path, HERE)}: anchor not unique "
                            f"(found {text.count(old)}): {old[:70]}")
            continue
        planned[path] = text.replace(old, new)
    if problems:
        print("[ABORT] Nothing written. Issues:")
        for pr in problems:
            print("  - " + pr)
        sys.exit(1)

    # create app files
    created = 0
    for rel, content in FILES.items():
        dest = os.path.join(APP, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if os.path.exists(dest):
            print(f"[skip] notifications/{rel} (exists)")
            continue
        with open(dest, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"[new]  notifications/{rel}")
        created += 1

    # write patches
    for path, new_text in planned.items():
        if new_text != open(path, encoding="utf-8").read():
            open(path, "w", encoding="utf-8").write(new_text)
            print(f"[edit] {os.path.relpath(path, HERE)}")
        else:
            print(f"[ok]   {os.path.relpath(path, HERE)} already wired")

    print(f"\nDone ({created} new files). Next:")
    print("  python manage.py makemigrations notifications")
    print("  python manage.py migrate")
    print("  python manage.py check")


if __name__ == "__main__":
    main()
