
from django.shortcuts import render

def crops_dashboard(request):
    return render(request, 'crops.html', {'crops': []})
