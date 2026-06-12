from django import forms
from analytics.models import Expense, Sale

class ExpenseForm(forms.ModelForm):
    class Meta:
        model = Expense
        fields = ['farm', 'category', 'description', 'amount', 'date']

class SaleForm(forms.ModelForm):
    class Meta:
        model = Sale
        fields = ['farm', 'product', 'quantity', 'unit', 'price_per_unit', 'total_price', 'buyer', 'date']
