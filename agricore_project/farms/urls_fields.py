from django.urls import path
from . import views

urlpatterns = [
    path('', views.field_list, name='field_list'),
    path('add/', views.field_create, name='field_create'),
    path('<int:pk>/edit/', views.field_update, name='field_update'),
    path('<int:pk>/delete/', views.field_delete, name='field_delete'),
]
