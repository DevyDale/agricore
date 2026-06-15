from rest_framework import serializers
from communications.models import Conversation, ConversationParticipant, Message

class ConversationSerializer(serializers.ModelSerializer):
    display_name = serializers.SerializerMethodField()
    other_username = serializers.SerializerMethodField()
    product_title = serializers.SerializerMethodField()

    class Meta:
        model = Conversation
        fields = '__all__'

    def _other_usernames(self, obj):
        request = self.context.get('request')
        me_id = getattr(getattr(request, 'user', None), 'id', None)
        return [p.user.username for p in obj.participants.select_related('user').all()
                if p.user_id != me_id]

    def get_other_username(self, obj):
        others = self._other_usernames(obj)
        return others[0] if len(others) == 1 else None

    def get_display_name(self, obj):
        others = self._other_usernames(obj)
        if len(others) == 1:
            return others[0]
        if len(others) > 1:
            return obj.title or 'Group chat'
        return obj.title or 'Conversation'

    def get_product_title(self, obj):
        return obj.product.title if obj.product_id else None

class ConversationParticipantSerializer(serializers.ModelSerializer):
    class Meta:
        model = ConversationParticipant
        fields = '__all__'

class MessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.CharField(source='sender.username', read_only=True)

    class Meta:
        model = Message
        fields = '__all__'
        read_only_fields = ['sender']