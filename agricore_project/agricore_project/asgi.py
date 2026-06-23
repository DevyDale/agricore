import os

from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agricore_project.settings')

# Initialise Django (populates the app registry) BEFORE importing anything that
# touches models/auth. The Channels JWT middleware imports django.contrib.auth
# models, and the websocket routing imports consumers that import models, so they
# must come after get_asgi_application(). Importing them earlier raises
# AppRegistryNotReady when daphne imports this module directly (e.g. on Render),
# even though it happens to work under `manage.py runserver`.
django_asgi_app = get_asgi_application()

from channels.routing import ProtocolTypeRouter, URLRouter  # noqa: E402
from accounts.middleware import JwtAuthMiddleware  # noqa: E402
from communications.routing import websocket_urlpatterns  # noqa: E402
from notifications.routing import (  # noqa: E402
    websocket_urlpatterns as notification_ws_urlpatterns,
)

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    "websocket": JwtAuthMiddleware(
        URLRouter(websocket_urlpatterns + notification_ws_urlpatterns)
    ),
})
