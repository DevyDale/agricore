from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from rest_framework.decorators import action
from rest_framework.response import Response
from communications.models import Conversation, ConversationParticipant, Message
from .serializers import ConversationSerializer, ConversationParticipantSerializer, MessageSerializer
from marketplace.models import Product

class ConversationViewSet(viewsets.ModelViewSet):
    queryset = Conversation.objects.all()
    serializer_class = ConversationSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(participants__user=self.request.user).distinct()

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
        if user == owner:
            # Owner chatting as self; allow but avoid duplicate participants creation issues.
            pass

        # Try to find existing conversation for this product with same participants
        convo = (Conversation.objects
                 .filter(product=product, participants__user=user)
                 .filter(participants__user=owner)
                 .first())

        if not convo:
            convo = Conversation.objects.create(
                title=f"Product: {product.title}",
                product=product,
            )
            ConversationParticipant.objects.bulk_create([
                ConversationParticipant(conversation=convo, user=user),
                ConversationParticipant(conversation=convo, user=owner),
            ])

        serializer = self.get_serializer(convo)
        return Response(serializer.data)

class ConversationParticipantViewSet(viewsets.ModelViewSet):
    queryset = ConversationParticipant.objects.all()
    serializer_class = ConversationParticipantSerializer
    permission_classes = [IsAuthenticated]

class MessageViewSet(viewsets.ModelViewSet):
    queryset = Message.objects.all()
    serializer_class = MessageSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(conversation__participants__user=self.request.user)