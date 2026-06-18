from rest_framework import viewsets, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.decorators import action
from rest_framework.response import Response
from django.core.files.storage import default_storage
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from communications.models import Conversation, ConversationParticipant, Message
from .serializers import ConversationSerializer, ConversationParticipantSerializer, MessageSerializer
from marketplace.models import Product
from accounts.models import CustomUser, Attachment


class ConversationViewSet(viewsets.ModelViewSet):
    queryset = Conversation.objects.all()
    serializer_class = ConversationSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(participants__user=self.request.user).distinct()

    @action(detail=False, methods=['post'], url_path='start-direct-chat')
    def start_direct_chat(self, request):
        """Create or return a private 1:1 conversation between the caller and another user."""
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
                 .filter(product__isnull=True, participants__user=me)
                 .filter(participants__user=other)
                 .distinct().first())
        if convo and convo.participants.count() != 2:
            convo = None

        if not convo:
            convo = Conversation.objects.create(title=f'{me.username}, {other.username}')
            ConversationParticipant.objects.bulk_create([
                ConversationParticipant(conversation=convo, user=me),
                ConversationParticipant(conversation=convo, user=other),
            ])

        return Response(self.get_serializer(convo).data)

    @action(detail=False, methods=['post'], url_path='start-product-chat')
    def start_product_chat(self, request):
        """Create or return a conversation for a product between buyer and store owner."""
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
                 .filter(participants__user=owner)
                 .first())
        if not convo:
            convo = Conversation.objects.create(title=f"Product: {product.title}", product=product)
            ConversationParticipant.objects.bulk_create([
                ConversationParticipant(conversation=convo, user=user),
                ConversationParticipant(conversation=convo, user=owner),
            ])

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
        qs = self.queryset.filter(conversation__participants__user=self.request.user)
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
        message = serializer.save(sender=request.user)

        if upload:
            name = default_storage.save(f'chat_attachments/{message.id}_{upload.name}', upload)
            url = default_storage.url(name)
            if url.startswith('/'):
                url = request.build_absolute_uri(url)
            att = Attachment.objects.create(
                owner_type='message', owner_id=message.id,
                filename=upload.name, url=url, uploaded_by=request.user,
            )
            message.attachment = att
            message.save(update_fields=['attachment'])

        self._broadcast(message)
        out = self.get_serializer(message)
        return Response(out.data, status=status.HTTP_201_CREATED,
                        headers=self.get_success_headers(out.data))

    def _broadcast(self, message):
        layer = get_channel_layer()
        if not layer:
            return
        att = message.attachment.url if message.attachment_id and message.attachment else None
        payload = {
            'id': message.id,
            'content': message.content,
            'sender': message.sender.username,
            'sender_id': message.sender_id,
            'sender_name': message.sender.username,
            'attachment_url': att,
            'created_at': str(message.created_at),
        }
        try:
            async_to_sync(layer.group_send)(
                f'conversation_{message.conversation_id}',
                {'type': 'chat.message', 'message': payload},
            )
        except Exception:
            pass
