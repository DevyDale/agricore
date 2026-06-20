from django.apps import AppConfig


class EscrowConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "escrow"

    def ready(self):
        # Register the money-movement audit signals.
        import escrow.audit_signals  # noqa: F401
