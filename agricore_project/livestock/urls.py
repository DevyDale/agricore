
from django.urls import path
from . import views

app_name = "livestock"

urlpatterns = [
    path('', views.livestock_list, name='livestock_list'),
    path('dashboard/', views.livestock_dashboard, name='livestock_dashboard'),
    path('add/', views.livestock_create, name='livestock_create'),
    path('<int:pk>/edit/', views.livestock_update, name='livestock_update'),
    path('<int:pk>/delete/', views.livestock_delete, name='livestock_delete'),
    path('animal/add/', views.animal_create, name='animal_create'),
]
