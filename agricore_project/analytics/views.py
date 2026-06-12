
from django.shortcuts import render, redirect, get_object_or_404
from django.urls import reverse
from django.contrib.auth.decorators import login_required
from analytics.models import Expense, Sale, ActivityLog, FarmFinance
from analytics.forms import ExpenseForm, SaleForm

@login_required
def expense_edit(request, pk):
    expense = get_object_or_404(Expense, pk=pk)
    if request.method == 'POST':
        form = ExpenseForm(request.POST, instance=expense)
        if form.is_valid():
            form.save()
            return redirect('analytics:expenses_dashboard')
    else:
        form = ExpenseForm(instance=expense)
    return render(request, 'analytics/expense_form.html', {'form': form, 'expense': expense})

@login_required
def expense_delete(request, pk):
    expense = get_object_or_404(Expense, pk=pk)
    if request.method == 'POST':
        expense.delete()
        return redirect('analytics:expenses_dashboard')
    return render(request, 'analytics/expense_confirm_delete.html', {'expense': expense})

def expenses_dashboard(request):
    expenses = Expense.objects.select_related('farm', 'created_by').order_by('-date')
    if request.method == 'POST':
        form = ExpenseForm(request.POST)
        if form.is_valid():
            expense = form.save(commit=False)
            if hasattr(request, 'user') and request.user.is_authenticated:
                expense.created_by = request.user
            expense.save()
            return redirect('analytics:expenses_dashboard')
    else:
        form = ExpenseForm()
    return render(request, 'expenses.html', {'expenses': expenses, 'form': form})
def dashboard_expenses(request):
    from analytics.models import Expense
    expenses = Expense.objects.select_related('farm', 'created_by').order_by('-date')
    return render(request, 'dashboard/expenses.html', {'expenses': expenses})
from django.shortcuts import render, redirect
from django.urls import reverse
from django.contrib.auth.decorators import login_required
from analytics.models import Expense, Sale, ActivityLog, FarmFinance
from analytics.forms import ExpenseForm, SaleForm


@login_required
def farm_finance_list(request):
    finances = FarmFinance.objects.select_related('farm').order_by('-date')
    return render(request, 'analytics/farm_finance_list.html', {'finances': finances})
def dashboard(request):
    return render(request, 'dashboard/index.html')

@login_required
def expense_list(request):
    expenses = Expense.objects.select_related('farm', 'created_by').order_by('-date')
    return render(request, 'analytics/expense_list.html', {'expenses': expenses})

@login_required
def expense_create(request):
    if request.method == 'POST':
        form = ExpenseForm(request.POST)
        if form.is_valid():
            expense = form.save(commit=False)
            expense.created_by = request.user
            expense.save()
            return redirect(reverse('analytics:expense_list'))
    else:
        form = ExpenseForm()
    return render(request, 'analytics/expense_form.html', {'form': form})

@login_required
def sale_list(request):
    sales = Sale.objects.select_related('farm', 'created_by').order_by('-date')
    return render(request, 'analytics/sale_list.html', {'sales': sales})

@login_required
def sale_create(request):
    if request.method == 'POST':
        form = SaleForm(request.POST)
        if form.is_valid():
            sale = form.save(commit=False)
            sale.created_by = request.user
            sale.save()
            return redirect(reverse('analytics:sale_list'))
    else:
        form = SaleForm()
    return render(request, 'analytics/sale_form.html', {'form': form})

@login_required
def activity_log_list(request):
    logs = ActivityLog.objects.select_related('user', 'content_type').order_by('-timestamp')[:200]
    return render(request, 'analytics/activity_log_list.html', {'activity_logs': logs})
