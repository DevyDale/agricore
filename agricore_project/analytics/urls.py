from django.urls import path
from . import views

app_name = 'analytics'

urlpatterns = [
    path('dashboard/', views.dashboard, name='dashboard'),
    path('expenses/', views.expense_list, name='expense_list'),
    path('expenses/add/', views.expense_create, name='expense_create'),
    path('expenses/<int:pk>/edit/', views.expense_edit, name='expense_edit'),
    path('expenses/<int:pk>/delete/', views.expense_delete, name='expense_delete'),
    path('sales/', views.sale_list, name='sale_list'),
    path('sales/add/', views.sale_create, name='sale_create'),
    path('activity-logs/', views.activity_log_list, name='activity_log_list'),
    path('dashboard/expenses/', views.dashboard_expenses, name='dashboard_expenses'),
    path('expenses/dashboard/', views.expenses_dashboard, name='expenses_dashboard'),
]
