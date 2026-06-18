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
