# farms/apps.py
from django.apps import AppConfig

class FarmsConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'farms'

    # DELETE THIS LINE:
    # def ready(self):
    #     import farms.signals