from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import CustomUser
from marketplace.models import Store


class StoreCreateTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = CustomUser.objects.create_user(username='testuser', email='test@example.com', password='testpass')
        self.client.force_authenticate(user=self.user)

    def test_create_store_sets_owner(self):
        payload = {
            'name': "Test Shop",
            'countries_of_operation': [],
            'description': 'desc',
            'owner_name': 'Test User',
            'owner_phone': '0700',
            'owner_email': 'test@example.com'
        }
        res = self.client.post('/api/stores/', payload, format='json')
        self.assertEqual(res.status_code, 201, msg=res.content)
        store = Store.objects.get(id=res.data['id'])
        self.assertEqual(store.owner, self.user)

    def test_create_store_requires_auth(self):
        anon = APIClient()
        res = anon.post('/api/stores/', {'name': 'x'}, format='json')
        self.assertEqual(res.status_code, 401)
