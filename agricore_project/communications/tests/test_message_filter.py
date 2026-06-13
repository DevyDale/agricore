from django.test import TestCase
from rest_framework.test import APIClient
from accounts.models import CustomUser
from communications.models import Conversation, ConversationParticipant, Message


class MessageConversationFilterTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = CustomUser.objects.create_user(username='msguser', email='msg@example.com', password='testpass')
        self.client.force_authenticate(user=self.user)
        self.conv1 = Conversation.objects.create(title='Conv 1')
        self.conv2 = Conversation.objects.create(title='Conv 2')
        ConversationParticipant.objects.create(conversation=self.conv1, user=self.user)
        ConversationParticipant.objects.create(conversation=self.conv2, user=self.user)
        for i in range(3):
            Message.objects.create(conversation=self.conv1, sender=self.user, content=f'c1-{i}')
        for i in range(2):
            Message.objects.create(conversation=self.conv2, sender=self.user, content=f'c2-{i}')

    def _results(self, response):
        data = response.data
        if isinstance(data, dict) and 'results' in data:
            return data['results']
        return data

    def test_filter_returns_only_that_conversation(self):
        res = self.client.get(f'/api/messages/?conversation={self.conv1.id}')
        self.assertEqual(res.status_code, 200, msg=res.content)
        self.assertEqual(len(self._results(res)), 3)

    def test_no_filter_returns_all_user_messages(self):
        res = self.client.get('/api/messages/')
        self.assertEqual(res.status_code, 200, msg=res.content)
        self.assertEqual(len(self._results(res)), 5)
