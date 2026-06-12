from rest_framework import serializers

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
