from django.db import models
from accounts.models import CustomUser, Attachment
from marketplace.models import Product


class Conversation(models.Model):
    TYPE_CHOICES = [
        ('direct', 'Direct'),     # private 1:1 inbox
        ('group', 'Group'),       # private, invite-only, admin-managed
        ('channel', 'Channel'),   # public, searchable, anyone can join
    ]
    title = models.CharField(max_length=255)
    type = models.CharField(max_length=10, choices=TYPE_CHOICES, default='direct')
    description = models.TextField(blank=True, default='')
    is_public = models.BooleanField(default=False)  # channels: discoverable + joinable
    creator = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True, blank=True,
                                related_name='created_conversations')
    product = models.ForeignKey(Product, on_delete=models.SET_NULL, null=True, blank=True,
                                related_name='conversations')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class ConversationParticipant(models.Model):
    ROLE_CHOICES = [('admin', 'Admin'), ('member', 'Member')]
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name='participants')
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    role = models.CharField(max_length=10, choices=ROLE_CHOICES, default='member')
    joined_at = models.DateTimeField(auto_now_add=True)
    left_at = models.DateTimeField(blank=True, null=True)


class Message(models.Model):
    TYPE_CHOICES = [
        ('text', 'Text'), ('image', 'Image'), ('file', 'File'),
        ('video', 'Video'), ('audio', 'Audio'),
    ]
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE)
    sender = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    content = models.TextField(blank=True, default='')
    message_type = models.CharField(max_length=10, choices=TYPE_CHOICES, default='text')
    attachment = models.ForeignKey(Attachment, on_delete=models.SET_NULL, null=True, blank=True)
    reply_to = models.ForeignKey('self', on_delete=models.SET_NULL, null=True, blank=True,
                                 related_name='replies')
    created_at = models.DateTimeField(auto_now_add=True)
    read_by = models.TextField(blank=True)  # comma-separated user IDs


class MessageReaction(models.Model):
    REACTION_CHOICES = [('like', 'Like'), ('dislike', 'Dislike')]
    message = models.ForeignKey(Message, on_delete=models.CASCADE, related_name='reactions')
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    reaction = models.CharField(max_length=10, choices=REACTION_CHOICES)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('message', 'user')


class UserPresence(models.Model):
    user = models.OneToOneField(CustomUser, on_delete=models.CASCADE, related_name='presence')
    is_online = models.BooleanField(default=False)
    last_seen = models.DateTimeField(null=True, blank=True)
