#!/usr/bin/env bash
# ============================================================================
# Agricore Dynamics — Chat Phase 1 (foundation + unbreak)
# Run from your Django project root:  .../agricore/agricore_project/
# Safe & reversible: backs up every file before touching it.
# ============================================================================
set -uo pipefail

# ---- 0. sanity: are we in the right place? ---------------------------------
if [ ! -f manage.py ]; then
  echo "X  No manage.py here. cd into your Django project root (the folder with manage.py) and re-run."
  exit 1
fi
FILES=(communications/api/views.py communications/api/serializers.py accounts/api/views.py templates/chats.html)
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then echo "X  Expected file missing: $f"; exit 1; fi
done

# ---- 1. backups -------------------------------------------------------------
STAMP=$(date +%Y%m%d-%H%M%S)
BK="phase1_backup_${STAMP}"
for f in "${FILES[@]}"; do mkdir -p "${BK}/$(dirname "$f")"; cp "$f" "${BK}/$f"; done
echo ">> Backups saved in ${BK}/"

# ---- 2. never edit main: move to a feature branch ---------------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  if [ "$CUR" = "main" ]; then
    echo ">> On 'main' — creating feature branch so main stays untouched."
  fi
  if git show-ref --verify --quiet refs/heads/feature/chat-phase1; then
    git checkout feature/chat-phase1
  else
    git checkout -b feature/chat-phase1
  fi
  echo ">> On branch: $(git rev-parse --abbrev-ref HEAD)"
else
  echo ">> Not a git repo — skipping branch step (backups still protect you)."
fi

# ---- 3. overwrite the two short communications files ------------------------
cat > communications/api/views.py << 'EOF'
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
EOF

cat > communications/api/serializers.py << 'EOF'
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
EOF
echo ">> Wrote communications/api/views.py + serializers.py"

# ---- 4. anchored patches for the large files (abort-safe, idempotent) -------
python3 - << 'PYEOF'
def patch(path, replacements):
    with open(path, 'r', encoding='utf-8') as fh:
        src = fh.read()
    original = src
    for i, (old, new) in enumerate(replacements, 1):
        if new in src:
            print(f"   - {path}: change #{i} already applied")
            continue
        if old not in src:
            print(f"   X {path}: anchor #{i} NOT FOUND -> file left untouched (reconcile manually; backup is safe)")
            return
        src = src.replace(old, new, 1)
    if src != original:
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(src)
        print(f"   OK {path}: patched")

acc_imports_old = "from rest_framework.permissions import IsAuthenticated, AllowAny"
acc_imports_new = (
    "from rest_framework.permissions import IsAuthenticated, AllowAny\n"
    "from rest_framework.decorators import action\n"
    "from django.db.models import Q"
)
acc_action_old = "        return [IsAuthenticated()]  # Require auth for other actions"
acc_action_new = (
    "        return [IsAuthenticated()]  # Require auth for other actions\n\n"
    "    @action(detail=False, methods=['get'], url_path='search')\n"
    "    def search(self, request):\n"
    "        q = (request.query_params.get('q') or '').strip()\n"
    "        results = []\n"
    "        if q:\n"
    "            qs = (CustomUser.objects\n"
    "                  .filter(Q(username__icontains=q) | Q(email__icontains=q))\n"
    "                  .exclude(id=request.user.id)[:20])\n"
    "            results = [{'id': u.id, 'username': u.username} for u in qs]\n"
    "        return Response(results)"
)
patch("accounts/api/views.py", [(acc_imports_old, acc_imports_new), (acc_action_old, acc_action_new)])

conv_old = """            const demoConversations = [
                { id: 1, title: 'Farmers Group', updated_at: new Date().toISOString() },
                { id: 2, title: 'Marketplace Channel', updated_at: new Date(Date.now() - 3600000).toISOString() },
                { id: 3, title: 'Direct Message - John', updated_at: new Date(Date.now() - 86400000).toISOString() },
                { id: 4, title: 'Crop Planning Group', updated_at: new Date(Date.now() - 172800000).toISOString() },
            ];

            try {
                let conversations = demoConversations;

                if (token) {
                    let url = '/api/conversations/';
                    if (search) url += `?search=${encodeURIComponent(search)}`;
                    const response = await fetch(url, {
                        headers: { 'Authorization': `Bearer ${token}` }
                    });
                    if (response.status === 401) {
                        alert('Session expired');
                        localStorage.clear();
                        window.location.href = 'authentication.html';
                        return;
                    }
                    if (response.ok) {
                        conversations = await response.json();
                    }
                }"""
conv_new = """            try {
                let conversations = [];

                if (!token) {
                    list.innerHTML = '<p class="text-center text-sm" style="color:var(--muted);">Please log in to see your conversations.</p>';
                    const cc0 = document.getElementById('conv-count');
                    if (cc0) cc0.textContent = 'Sign in';
                    return;
                }

                let url = '/api/conversations/';
                if (search) url += `?search=${encodeURIComponent(search)}`;
                const response = await fetch(url, {
                    headers: { 'Authorization': `Bearer ${token}` }
                });
                if (response.status === 401) {
                    alert('Session expired');
                    localStorage.clear();
                    window.location.href = 'authentication.html';
                    return;
                }
                if (response.ok) {
                    conversations = await response.json();
                }"""

msg_old = """            const demoMessages = [
                { id: 1, sender: 'John Farmer', sender_id: 1, content: 'Hello everyone! How are the crops this season?', created_at: new Date(Date.now() - 3600000).toISOString() },
                { id: 2, sender: 'Mary Smith', sender_id: 2, content: 'Pretty good! The rain last week really helped.', created_at: new Date(Date.now() - 3000000).toISOString() },
                { id: 3, sender: 'You', sender_id: localStorage.getItem('user_id') || 3, content: 'Great to hear! Anyone need supplies from the marketplace?', created_at: new Date(Date.now() - 1800000).toISOString() },
            ];

            try {
                let messages = demoMessages;

                if (token) {
                    const response = await fetch(`/api/messages/?conversation=${conversationId}`, {
                        headers: { 'Authorization': `Bearer ${token}` }
                    });
                    if (response.status === 401) {
                        alert('Session expired');
                        localStorage.clear();
                        window.location.href = 'authentication.html';
                        return;
                    }
                    if (response.ok) {
                        messages = await response.json();
                    }
                }"""
msg_new = """            try {
                let messages = [];

                if (!token) {
                    messageList.innerHTML = '<p class="text-gray-500 text-sm text-center py-8">Please log in to view messages.</p>';
                    return;
                }

                const response = await fetch(`/api/messages/?conversation=${conversationId}`, {
                    headers: { 'Authorization': `Bearer ${token}` }
                });
                if (response.status === 401) {
                    alert('Session expired');
                    localStorage.clear();
                    window.location.href = 'authentication.html';
                    return;
                }
                if (response.ok) {
                    messages = await response.json();
                }"""

patch("templates/chats.html", [(conv_old, conv_new), (msg_old, msg_new)])
PYEOF

# ---- 5. parse-check the python we touched -----------------------------------
echo ">> Syntax-checking Python files..."
for p in communications/api/views.py communications/api/serializers.py accounts/api/views.py; do
  python3 -c "import ast; ast.parse(open('$p').read())" && echo "   ok: $p" || echo "   FAILED: $p"
done

# ---- 6. verify ---------------------------------------------------------------
echo ">> makemigrations check (expect: 'No changes detected'):"
python manage.py makemigrations --check --dry-run
echo ">> Running tests (communications, accounts):"
python manage.py test communications accounts --keepdb

echo ""
echo "============================================================"
echo "Phase 1 applied on branch $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'n/a')."
echo "Review:   git diff"
echo "Rollback: cp -a ${BK}/. .    (restores the 4 original files)"
echo "============================================================"
