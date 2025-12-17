import os

from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import WebsocketDenier
from accounts.middleware import JwtAuthMiddleware
from communications.routing import websocket_urlpatterns

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agricore_project.settings')

django_asgi_app = get_asgi_application()

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    "websocket": JwtAuthMiddleware(
        URLRouter(websocket_urlpatterns)
    ),
})