from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from .models import Message, Conversation
import json

# Your original is fine; added @database_sync_to_async for safety if needed
class ChatConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.conversation_id = self.scope['url_route']['kwargs']['conversation_id']
        self.group_name = f'conversation_{self.conversation_id}'

        # Check if user is participant
        if await self.is_participant():
            await self.channel_layer.group_add(self.group_name, self.channel_name)
            await self.accept()
        else:
            await self.close()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data):
        data = json.loads(text_data)
        message = await self.save_message(data['content'])
        await self.channel_layer.group_send(
            self.group_name,
            {'type': 'chat.message', 'message': message}
        )

    async def chat_message(self, event):
        await self.send(text_data=json.dumps(event['message']))

    @database_sync_to_async
    def is_participant(self):
        conversation = Conversation.objects.get(id=self.conversation_id)
        return conversation.participants.filter(user=self.scope['user']).exists()

    @database_sync_to_async
    def save_message(self, content):
        message = Message.objects.create(
            conversation_id=self.conversation_id,
            sender=self.scope['user'],
            content=content
        )
        return {'id': message.id, 'content': message.content, 'sender': message.sender.username, 'created_at': str(message.created_at)}