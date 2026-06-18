from rest_framework import serializers
from django.utils import timezone
from datetime import timedelta
from communications.models import (
    Conversation, ConversationParticipant, Message, MessageReaction, UserPresence,
)


def _presence_for(user):
    """Return (is_online, last_seen_iso) treating a heartbeat in the last 60s as online."""
    pres = getattr(user, 'presence', None)
    if not pres:
        return False, None
    online = bool(pres.is_online and pres.last_seen and
                  pres.last_seen > timezone.now() - timedelta(seconds=60))
    return online, (pres.last_seen.isoformat() if pres.last_seen else None)


class ConversationSerializer(serializers.ModelSerializer):
    display_name = serializers.SerializerMethodField()
    product_title = serializers.CharField(source='product.title', read_only=True, default=None)
    creator_username = serializers.CharField(source='creator.username', read_only=True, default=None)
    my_role = serializers.SerializerMethodField()
    participant_count = serializers.SerializerMethodField()
    other_online = serializers.SerializerMethodField()
    other_last_seen = serializers.SerializerMethodField()

    class Meta:
        model = Conversation
        fields = ['id', 'title', 'type', 'description', 'is_public', 'creator', 'creator_username',
                  'product', 'product_title', 'display_name', 'my_role', 'participant_count',
                  'other_online', 'other_last_seen', 'created_at', 'updated_at']
        read_only_fields = ['creator']

    def _me(self):
        request = self.context.get('request')
        return getattr(request, 'user', None) if request else None

    def _others(self, obj):
        me = self._me()
        me_id = getattr(me, 'id', None)
        return [p.user for p in obj.participants.select_related('user').all() if p.user_id != me_id]

    def get_display_name(self, obj):
        if obj.type == 'direct':
            others = self._others(obj)
            if len(others) == 1:
                return others[0].username
        return obj.title

    def get_my_role(self, obj):
        me = self._me()
        if not me:
            return None
        p = obj.participants.filter(user=me).first()
        return p.role if p else None

    def get_participant_count(self, obj):
        return obj.participants.count()

    def get_other_online(self, obj):
        if obj.type != 'direct':
            return None
        others = self._others(obj)
        return _presence_for(others[0])[0] if len(others) == 1 else None

    def get_other_last_seen(self, obj):
        if obj.type != 'direct':
            return None
        others = self._others(obj)
        return _presence_for(others[0])[1] if len(others) == 1 else None


class ConversationParticipantSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source='user.username', read_only=True)
    online = serializers.SerializerMethodField()
    last_seen = serializers.SerializerMethodField()

    class Meta:
        model = ConversationParticipant
        fields = ['id', 'conversation', 'user', 'username', 'role', 'online', 'last_seen', 'joined_at']

    def get_online(self, obj):
        return _presence_for(obj.user)[0]

    def get_last_seen(self, obj):
        return _presence_for(obj.user)[1]


class MessageSerializer(serializers.ModelSerializer):
    sender = serializers.PrimaryKeyRelatedField(read_only=True)
    sender_id = serializers.IntegerField(source='sender.id', read_only=True)
    sender_name = serializers.CharField(source='sender.username', read_only=True)
    attachment_url = serializers.SerializerMethodField()
    reply_preview = serializers.SerializerMethodField()
    reactions = serializers.SerializerMethodField()
    content = serializers.CharField(required=False, allow_blank=True, default='')

    class Meta:
        model = Message
        fields = ['id', 'conversation', 'sender', 'sender_id', 'sender_name', 'content',
                  'message_type', 'attachment', 'attachment_url', 'reply_to', 'reply_preview',
                  'reactions', 'created_at', 'read_by']
        read_only_fields = ['sender', 'attachment', 'message_type', 'read_by', 'created_at']

    def get_attachment_url(self, obj):
        return obj.attachment.url if obj.attachment_id and obj.attachment else None

    def get_reply_preview(self, obj):
        if not obj.reply_to_id or not obj.reply_to:
            return None
        r = obj.reply_to
        snippet = (r.content or '')[:80] or f'[{r.message_type}]'
        return {'id': r.id, 'sender_name': r.sender.username, 'snippet': snippet}

    def get_reactions(self, obj):
        likes = dislikes = 0
        mine = None
        me = getattr(self.context.get('request'), 'user', None)
        for rx in obj.reactions.all():
            if rx.reaction == 'like':
                likes += 1
            elif rx.reaction == 'dislike':
                dislikes += 1
            if me and rx.user_id == me.id:
                mine = rx.reaction
        return {'like': likes, 'dislike': dislikes, 'mine': mine}
