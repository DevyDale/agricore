#!/usr/bin/env python3
"""
Adds a `start-store-chat` action to the conversations API so the store profile
page's "Chat with store" button works (mirrors the existing start-product-chat).
Idempotent: safe to run more than once. Run from the agricore_project/ directory.
"""
import os, sys

def find_file(name):
    if os.path.exists(name):
        return name
    for root, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        if os.path.basename(name) in files and name.replace('./', '') in os.path.join(root, os.path.basename(name)).replace('./', ''):
            return os.path.join(root, os.path.basename(name))
    # fallback: match by tail path
    tail = name.split('/')[-2:]
    for root, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for fn in files:
            p = os.path.join(root, fn)
            if p.replace('./', '').endswith('/'.join(tail)):
                return p
    return None

path = find_file('communications/api/views.py')
if not path:
    print("ERROR: could not locate communications/api/views.py (run me from agricore_project/)")
    sys.exit(1)

src = open(path, encoding='utf-8').read()

if 'start-store-chat' in src:
    print("Already patched: start-store-chat exists. Nothing to do.")
    sys.exit(0)

# 1) ensure Store is imported alongside Product
import_anchor = 'from marketplace.models import Product'
if import_anchor in src and 'from marketplace.models import Product, Store' not in src:
    src = src.replace(import_anchor, 'from marketplace.models import Product, Store', 1)
elif 'from marketplace.models import' not in src:
    # add an import after the serializers import line as a fallback
    src = src.replace(
        'from .serializers import ConversationSerializer, ConversationParticipantSerializer, MessageSerializer',
        'from .serializers import ConversationSerializer, ConversationParticipantSerializer, MessageSerializer\nfrom marketplace.models import Product, Store',
        1,
    )

# 2) insert the new action right after start_product_chat's return
action_code = '''
    @action(detail=False, methods=['post'], url_path='start-store-chat')
    def start_store_chat(self, request):
        """Create or return a conversation between the current user and a store owner."""
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
                 .filter(participants__user=owner)
                 .first())

        if not convo:
            convo = Conversation.objects.create(title=title)
            parts = [ConversationParticipant(conversation=convo, user=user)]
            if owner and owner != user:
                parts.append(ConversationParticipant(conversation=convo, user=owner))
            ConversationParticipant.objects.bulk_create(parts)

        serializer = self.get_serializer(convo)
        return Response(serializer.data)
'''

# Anchor: the end of start_product_chat is the line `        return Response(serializer.data)`
# that sits inside ConversationViewSet. Insert after the FIRST such return that follows
# the start_product_chat definition.
marker = 'def start_product_chat(self, request):'
idx = src.find(marker)
if idx == -1:
    print("ERROR: start_product_chat not found; structure differs from expected.")
    sys.exit(1)
ret_idx = src.find('        return Response(serializer.data)', idx)
if ret_idx == -1:
    print("ERROR: could not find the end of start_product_chat.")
    sys.exit(1)
insert_at = ret_idx + len('        return Response(serializer.data)')
new_src = src[:insert_at] + '\n' + action_code + src[insert_at:]

open(path, 'w', encoding='utf-8').write(new_src)
print(f"Patched {path}: added start-store-chat action.")
print("Restart the server. Endpoint: POST /api/conversations/start-store-chat/  body {\"store\": <id>}")
