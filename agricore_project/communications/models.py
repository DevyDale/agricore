from django.db import models
from accounts.models import CustomUser, Attachment
from marketplace.models import Product

class Conversation(models.Model):
    title = models.CharField(max_length=255)
    product = models.ForeignKey(Product, on_delete=models.SET_NULL, null=True, blank=True, related_name='conversations')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class ConversationParticipant(models.Model):
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name='participants')
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    joined_at = models.DateTimeField(auto_now_add=True)
    left_at = models.DateTimeField(blank=True, null=True)

class Message(models.Model):
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE)
    sender = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    content = models.TextField()
    attachment = models.ForeignKey(Attachment, on_delete=models.SET_NULL, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    read_by = models.TextField(blank=True)  # e.g., comma-separated user IDs