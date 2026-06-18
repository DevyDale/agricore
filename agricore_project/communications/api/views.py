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
