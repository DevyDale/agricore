from rest_framework import serializers
from communications.models import Conversation, ConversationParticipant, Message


class ConversationSerializer(serializers.ModelSerializer):
    display_name = serializers.SerializerMethodField()
    product_title = serializers.CharField(source='product.title', read_only=True, default=None)

    class Meta:
        model = Conversation
        fields = ['id', 'title', 'product', 'product_title', 'display_name',
                  'created_at', 'updated_at']

    def get_display_name(self, obj):
        request = self.context.get('request')
        me = getattr(request, 'user', None) if request else None
        parts = list(obj.participants.select_related('user').all())
        if me is not None and len(parts) == 2:
            others = [p.user for p in parts if p.user_id != me.id]
            if others:
                return others[0].username
        return obj.title


class ConversationParticipantSerializer(serializers.ModelSerializer):
    class Meta:
        model = ConversationParticipant
        fields = '__all__'


class MessageSerializer(serializers.ModelSerializer):
    sender = serializers.PrimaryKeyRelatedField(read_only=True)
    sender_id = serializers.IntegerField(source='sender.id', read_only=True)
    sender_name = serializers.CharField(source='sender.username', read_only=True)
    attachment_url = serializers.SerializerMethodField()
    content = serializers.CharField(required=False, allow_blank=True, default='')

    class Meta:
        model = Message
        fields = ['id', 'conversation', 'sender', 'sender_id', 'sender_name',
                  'content', 'attachment', 'attachment_url', 'created_at', 'read_by']
        read_only_fields = ['attachment', 'read_by', 'created_at']

    def get_attachment_url(self, obj):
        return obj.attachment.url if obj.attachment_id and obj.attachment else None
