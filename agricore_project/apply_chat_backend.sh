#!/usr/bin/env bash
# ============================================================================
# Agricore Dynamics — Chat backend build (command 1 of 2)
# Adds: conversation types (direct/group/channel), admin roles, public channels
#       + join, member add/remove, message reactions, replies, file/audio/video
#       message types, presence/last-seen, admin-only hard delete.
# Run from the Django project root (folder with manage.py). Reversible.
# ============================================================================
set -uo pipefail

if [ ! -f manage.py ] || [ ! -d communications ]; then
  echo "X  Run from your Django project root (folder with manage.py + communications/)."; exit 1
fi

FILES=(communications/models.py communications/api/serializers.py communications/api/views.py communications/consumers.py)
STAMP=$(date +%Y%m%d-%H%M%S); BK="chatbackend_backup_${STAMP}"
for f in "${FILES[@]}"; do mkdir -p "${BK}/$(dirname "$f")"; cp "$f" "${BK}/$f" 2>/dev/null; done
echo ">> Backups in ${BK}/"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git show-ref --verify --quiet refs/heads/dev && git checkout dev >/dev/null 2>&1 || true
  if git show-ref --verify --quiet refs/heads/feature/chat-backend; then
    git checkout feature/chat-backend
  else
    git checkout -b feature/chat-backend
  fi
  echo ">> On branch $(git rev-parse --abbrev-ref HEAD) (main untouched)"
fi

cat > communications/models.py << 'MODELS_EOF'
from django.db import models
from accounts.models import CustomUser, Attachment
from marketplace.models import Product


class Conversation(models.Model):
    TYPE_CHOICES = [
        ('direct', 'Direct'),     # private 1:1 inbox
        ('group', 'Group'),       # private, invite-only, admin-managed
        ('channel', 'Channel'),   # public, searchable, anyone can join
    ]
    title = models.CharField(max_length=255)
    type = models.CharField(max_length=10, choices=TYPE_CHOICES, default='direct')
    description = models.TextField(blank=True, default='')
    is_public = models.BooleanField(default=False)  # channels: discoverable + joinable
    creator = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True, blank=True,
                                related_name='created_conversations')
    product = models.ForeignKey(Product, on_delete=models.SET_NULL, null=True, blank=True,
                                related_name='conversations')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class ConversationParticipant(models.Model):
    ROLE_CHOICES = [('admin', 'Admin'), ('member', 'Member')]
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name='participants')
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    role = models.CharField(max_length=10, choices=ROLE_CHOICES, default='member')
    joined_at = models.DateTimeField(auto_now_add=True)
    left_at = models.DateTimeField(blank=True, null=True)


class Message(models.Model):
    TYPE_CHOICES = [
        ('text', 'Text'), ('image', 'Image'), ('file', 'File'),
        ('video', 'Video'), ('audio', 'Audio'),
    ]
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE)
    sender = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    content = models.TextField(blank=True, default='')
    message_type = models.CharField(max_length=10, choices=TYPE_CHOICES, default='text')
    attachment = models.ForeignKey(Attachment, on_delete=models.SET_NULL, null=True, blank=True)
    reply_to = models.ForeignKey('self', on_delete=models.SET_NULL, null=True, blank=True,
                                 related_name='replies')
    created_at = models.DateTimeField(auto_now_add=True)
    read_by = models.TextField(blank=True)  # comma-separated user IDs


class MessageReaction(models.Model):
    REACTION_CHOICES = [('like', 'Like'), ('dislike', 'Dislike')]
    message = models.ForeignKey(Message, on_delete=models.CASCADE, related_name='reactions')
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    reaction = models.CharField(max_length=10, choices=REACTION_CHOICES)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('message', 'user')


class UserPresence(models.Model):
    user = models.OneToOneField(CustomUser, on_delete=models.CASCADE, related_name='presence')
    is_online = models.BooleanField(default=False)
    last_seen = models.DateTimeField(null=True, blank=True)
MODELS_EOF

cat > communications/api/serializers.py << 'SER_EOF'
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
SER_EOF

cat > communications/api/views.py << 'VIEWS_EOF'
import mimetypes

from rest_framework import viewsets, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.exceptions import PermissionDenied
from django.core.files.storage import default_storage
from django.db.models import Q
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from communications.models import (
    Conversation, ConversationParticipant, Message, MessageReaction,
)
from .serializers import (
    ConversationSerializer, ConversationParticipantSerializer, MessageSerializer,
)
from marketplace.models import Product, Store
from accounts.models import CustomUser, Attachment


def _broadcast(conversation_id, event):
    layer = get_channel_layer()
    if not layer:
        return
    try:
        async_to_sync(layer.group_send)(f'conversation_{conversation_id}', event)
    except Exception:
        pass


def _msg_type_for(filename):
    guess = (mimetypes.guess_type(filename)[0] or '').lower()
    if guess.startswith('image/'):
        return 'image'
    if guess.startswith('video/'):
        return 'video'
    if guess.startswith('audio/'):
        return 'audio'
    return 'file'


class ConversationViewSet(viewsets.ModelViewSet):
    queryset = Conversation.objects.all()
    serializer_class = ConversationSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(participants__user=self.request.user).distinct()

    def perform_create(self, serializer):
        # Creator becomes an admin participant so groups/channels show up + are manageable.
        convo = serializer.save(creator=self.request.user)
        if not convo.participants.filter(user=self.request.user).exists():
            ConversationParticipant.objects.create(
                conversation=convo, user=self.request.user, role='admin')

    def _require_admin(self, convo):
        p = convo.participants.filter(user=self.request.user).first()
        if not p or p.role != 'admin':
            raise PermissionDenied('Only an admin of this conversation can do that.')

    def destroy(self, request, *args, **kwargs):
        convo = self.get_object()
        self._require_admin(convo)  # hard-delete for everyone, admins only
        return super().destroy(request, *args, **kwargs)

    # ---- discovery / membership ------------------------------------------------
    @action(detail=False, methods=['get'], url_path='public')
    def public(self, request):
        """List public channels anyone can search and join."""
        qs = Conversation.objects.filter(type='channel', is_public=True)
        q = (request.query_params.get('search') or request.query_params.get('q') or '').strip()
        if q:
            qs = qs.filter(Q(title__icontains=q) | Q(description__icontains=q))
        data = self.get_serializer(qs.distinct()[:50], many=True).data
        return Response(data)

    @action(detail=True, methods=['post'], url_path='join')
    def join(self, request, pk=None):
        convo = self.get_object_any()
        if not (convo.type == 'channel' and convo.is_public):
            return Response({'detail': 'This conversation is not open to join.'}, status=403)
        ConversationParticipant.objects.get_or_create(
            conversation=convo, user=request.user, defaults={'role': 'member'})
        return Response(self.get_serializer(convo).data)

    @action(detail=True, methods=['post'], url_path='leave')
    def leave(self, request, pk=None):
        convo = self.get_object()
        convo.participants.filter(user=request.user).delete()
        return Response({'detail': 'left'})

    @action(detail=True, methods=['post'], url_path='add-member')
    def add_member(self, request, pk=None):
        convo = self.get_object()
        self._require_admin(convo)
        uid = request.data.get('user')
        try:
            user = CustomUser.objects.get(id=uid)
        except CustomUser.DoesNotExist:
            return Response({'detail': 'User not found'}, status=404)
        ConversationParticipant.objects.get_or_create(
            conversation=convo, user=user, defaults={'role': 'member'})
        return Response(ConversationParticipantSerializer(
            convo.participants.select_related('user').all(), many=True).data)

    @action(detail=True, methods=['post'], url_path='remove-member')
    def remove_member(self, request, pk=None):
        convo = self.get_object()
        self._require_admin(convo)
        uid = request.data.get('user')
        if str(uid) == str(convo.creator_id):
            return Response({'detail': "Can't remove the creator."}, status=400)
        convo.participants.filter(user_id=uid).delete()
        return Response(ConversationParticipantSerializer(
            convo.participants.select_related('user').all(), many=True).data)

    @action(detail=True, methods=['get'], url_path='members')
    def members(self, request, pk=None):
        convo = self.get_object()
        return Response(ConversationParticipantSerializer(
            convo.participants.select_related('user').all(), many=True).data)

    def get_object_any(self):
        """Like get_object but not restricted to conversations the user is already in
        (needed so a user can JOIN a public channel they're not yet part of)."""
        obj = Conversation.objects.get(pk=self.kwargs['pk'])
        return obj

    # ---- chat starters (preserved) --------------------------------------------
    @action(detail=False, methods=['post'], url_path='start-direct-chat')
    def start_direct_chat(self, request):
        other_id = request.data.get('user')
        if not other_id:
            return Response({'detail': 'user is required'}, status=400)
        try:
            other = CustomUser.objects.get(id=other_id)
        except CustomUser.DoesNotExist:
            return Response({'detail': 'User not found'}, status=404)
        me = request.user
        if other.id == me.id:
            return Response({'detail': 'Cannot start a chat with yourself'}, status=400)

        convo = (Conversation.objects
                 .filter(type='direct', participants__user=me)
                 .filter(participants__user=other).distinct().first())
        if convo and convo.participants.count() != 2:
            convo = None
        if not convo:
            convo = Conversation.objects.create(title=other.username, type='direct', creator=me)
            ConversationParticipant.objects.bulk_create([
                ConversationParticipant(conversation=convo, user=me, role='admin'),
                ConversationParticipant(conversation=convo, user=other, role='member'),
            ])
        return Response(self.get_serializer(convo).data)

    @action(detail=False, methods=['post'], url_path='start-product-chat')
    def start_product_chat(self, request):
        product_id = request.data.get('product')
        if not product_id:
            return Response({'detail': 'product is required'}, status=400)
        try:
            product = Product.objects.select_related('store__owner').get(id=product_id)
        except Product.DoesNotExist:
            return Response({'detail': 'Product not found'}, status=404)
        user = request.user
        owner = product.store.owner
        convo = (Conversation.objects
                 .filter(product=product, participants__user=user)
                 .filter(participants__user=owner).first())
        if not convo:
            convo = Conversation.objects.create(
                title=f"Product: {product.title}", type='direct', product=product, creator=user)
            ConversationParticipant.objects.bulk_create([
                ConversationParticipant(conversation=convo, user=user, role='admin'),
                ConversationParticipant(conversation=convo, user=owner, role='member'),
            ])
        return Response(self.get_serializer(convo).data)

    @action(detail=False, methods=['post'], url_path='start-store-chat')
    def start_store_chat(self, request):
        store_id = request.data.get('store')
        if not store_id:
            return Response({'detail': 'store is required'}, status=400)
        try:
            store = Store.objects.select_related('owner').get(id=store_id)
        except Store.DoesNotExist:
            return Response({'detail': 'Store not found'}, status=404)
        user = request.user
        owner = store.owner
        title = f"Store: {store.name}"
        convo = (Conversation.objects
                 .filter(title=title, participants__user=user)
                 .filter(participants__user=owner).first())
        if not convo:
            convo = Conversation.objects.create(title=title, type='direct', creator=user)
            parts = [ConversationParticipant(conversation=convo, user=user, role='admin')]
            if owner and owner != user:
                parts.append(ConversationParticipant(conversation=convo, user=owner, role='member'))
            ConversationParticipant.objects.bulk_create(parts)
        return Response(self.get_serializer(convo).data)


class ConversationParticipantViewSet(viewsets.ModelViewSet):
    queryset = ConversationParticipant.objects.all()
    serializer_class = ConversationParticipantSerializer
    permission_classes = [IsAuthenticated]


class MessageViewSet(viewsets.ModelViewSet):
    queryset = Message.objects.all()
    serializer_class = MessageSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = self.queryset.filter(conversation__participants__user=self.request.user).distinct()
        conv = self.request.query_params.get('conversation')
        if conv:
            qs = qs.filter(conversation_id=conv)
        return qs.order_by('created_at')

    def create(self, request, *args, **kwargs):
        data = request.data.copy()
        upload = request.FILES.get('attachment')
        data.pop('attachment', None)

        serializer = self.get_serializer(data=data)
        serializer.is_valid(raise_exception=True)
        conversation = serializer.validated_data.get('conversation')
        if conversation and not conversation.participants.filter(user=request.user).exists():
            raise PermissionDenied('You are not a participant in this conversation.')

        message = serializer.save(sender=request.user)

        if upload:
            name = default_storage.save(f'chat_attachments/{message.id}_{upload.name}', upload)
            url = default_storage.url(name)
            if url.startswith('/'):
                url = request.build_absolute_uri(url)
            att = Attachment.objects.create(
                owner_type='message', owner_id=message.id,
                filename=upload.name, url=url, uploaded_by=request.user)
            message.attachment = att
            message.message_type = _msg_type_for(upload.name)
            message.save(update_fields=['attachment', 'message_type'])

        out = self.get_serializer(message)
        _broadcast(message.conversation_id, {'type': 'chat.message', 'message': out.data})
        return Response(out.data, status=status.HTTP_201_CREATED,
                        headers=self.get_success_headers(out.data))

    @action(detail=True, methods=['post'], url_path='react')
    def react(self, request, pk=None):
        message = self.get_object()
        reaction = request.data.get('reaction')
        if reaction not in ('like', 'dislike'):
            return Response({'detail': "reaction must be 'like' or 'dislike'"}, status=400)
        existing = MessageReaction.objects.filter(message=message, user=request.user).first()
        if existing and existing.reaction == reaction:
            existing.delete()  # toggle off
        else:
            MessageReaction.objects.update_or_create(
                message=message, user=request.user, defaults={'reaction': reaction})
        out = self.get_serializer(message)
        _broadcast(message.conversation_id,
                   {'type': 'chat.message', 'message': out.data, 'update': True})
        return Response(out.data)
VIEWS_EOF

cat > communications/consumers.py << 'CONS_EOF'
import json

from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from django.utils import timezone
from django.contrib.auth.models import AnonymousUser

from .models import Message, Conversation, UserPresence
from accounts.models import CustomUser


class ChatConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.conversation_id = self.scope['url_route']['kwargs']['conversation_id']
        self.group_name = f'conversation_{self.conversation_id}'
        self.user = self.scope.get('user')  # set by JwtAuthMiddleware

        if not self.user or isinstance(self.user, AnonymousUser) or not await self.is_participant():
            await self.close()
            return

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        await self.set_presence(True)
        await self.channel_layer.group_send(self.group_name, {
            'type': 'presence.event',
            'presence': {'user_id': self.user.id, 'username': self.user.username,
                         'online': True, 'last_seen': timezone.now().isoformat()},
        })

    async def disconnect(self, close_code):
        try:
            if getattr(self, 'user', None) and not isinstance(self.user, AnonymousUser):
                await self.set_presence(False)
                await self.channel_layer.group_send(self.group_name, {
                    'type': 'presence.event',
                    'presence': {'user_id': self.user.id, 'username': self.user.username,
                                 'online': False, 'last_seen': timezone.now().isoformat()},
                })
        except Exception:
            pass
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data):
        # Frontend posts messages over REST; this stays for plain-text WS sends.
        try:
            data = json.loads(text_data)
        except Exception:
            return
        content = data.get('content')
        if not content:
            return
        message = await self.save_message(content)
        await self.channel_layer.group_send(
            self.group_name, {'type': 'chat.message', 'message': message})

    # ---- group event handlers --------------------------------------------------
    async def chat_message(self, event):
        payload = event['message']
        if event.get('update'):
            payload = dict(payload, _update=True)
        await self.send(text_data=json.dumps(payload))

    async def presence_event(self, event):
        await self.send(text_data=json.dumps({'_presence': event['presence']}))

    # ---- db helpers ------------------------------------------------------------
    @database_sync_to_async
    def is_participant(self):
        try:
            convo = Conversation.objects.get(id=self.conversation_id)
        except Conversation.DoesNotExist:
            return False
        return convo.participants.filter(user=self.user).exists()

    @database_sync_to_async
    def set_presence(self, online):
        UserPresence.objects.update_or_create(
            user=self.user, defaults={'is_online': online, 'last_seen': timezone.now()})

    @database_sync_to_async
    def save_message(self, content):
        message = Message.objects.create(
            conversation_id=self.conversation_id, sender=self.user, content=content)
        return {'id': message.id, 'content': message.content, 'message_type': 'text',
                'sender': message.sender.username, 'sender_id': message.sender_id,
                'sender_name': message.sender.username, 'created_at': str(message.created_at)}
CONS_EOF

echo ">> Wrote backend files. Parse-checking..."
for p in communications/models.py communications/api/serializers.py communications/api/views.py communications/consumers.py; do
  python3 -c "import ast; ast.parse(open('$p').read())" && echo "   ok $p" || { echo "   PARSE FAIL $p"; exit 1; }
done

echo ">> makemigrations communications:"
python manage.py makemigrations communications || { echo "X makemigrations failed"; exit 1; }
echo ">> migrate:"
python manage.py migrate || { echo "X migrate failed"; exit 1; }
echo ">> check:"
python manage.py check
echo ">> tests:"
python manage.py test communications accounts --keepdb

echo ""
echo "============================================================"
echo "Backend applied on $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo n/a)."
echo "Review:    git diff $BK 2>/dev/null; git diff"
echo "Rollback:  python manage.py migrate communications <previous_number>  &&  cp -a ${BK}/. ."
echo "Next:      the rewritten chats.html (command 2) that uses all of this."
echo "============================================================"
