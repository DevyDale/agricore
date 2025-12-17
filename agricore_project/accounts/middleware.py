from urllib.parse import parse_qs
from channels.db import database_sync_to_async
from rest_framework_simplejwt.tokens import UntypedToken
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from django.contrib.auth.models import AnonymousUser
from channels.middleware import BaseMiddleware
from django.conf import settings
from jwt import decode as jwt_decode

@database_sync_to_async
def get_user(user_id):
    from .models import CustomUser
    try:
        return CustomUser.objects.get(id=user_id)
    except CustomUser.DoesNotExist:
        return AnonymousUser()

class JwtAuthMiddleware(BaseMiddleware):
    async def __call__(self, scope, receive, send):
        query_string = scope['query_string'].decode()
        token_param = parse_qs(query_string).get('token')
        if token_param:
            token = token_param[0]
            try:
                UntypedToken(token)
                decoded_data = jwt_decode(token, settings.SIMPLE_JWT['SIGNING_KEY'], algorithms=[settings.SIMPLE_JWT['ALGORITHM']])
                scope['user'] = await get_user(decoded_data['user_id'])
            except (InvalidToken, TokenError):
                scope['user'] = AnonymousUser()
        else:
            scope['user'] = AnonymousUser()
        return await super().__call__(scope, receive, send)