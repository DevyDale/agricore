"""Helper any app can import: `from notifications.services import notify`."""
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
