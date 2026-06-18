from celery import shared_task


@shared_task
def auto_release_due_escrows():
    """Periodic task: release escrows whose dispute window has elapsed.
    Wire into Celery beat, or rely on the lazy sweep in EscrowViewSet.list()."""
    from escrow.api.views import release_due_escrows
    return release_due_escrows()
