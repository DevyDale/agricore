from django.shortcuts import render, get_object_or_404, redirect
from .models import Field, Farm
from django.urls import reverse

def field_list(request):
    field_list = Field.objects.all()
    return render(request, 'fields/field_list.html', {'field_list': field_list})

def field_create(request):
    if request.method == 'POST':
        name = request.POST.get('name')
        purpose = request.POST.get('purpose')
        farm = request.POST.get('farm')
        total_size = request.POST.get('total_size')
        size_unit = request.POST.get('size_unit')
        soil_type = request.POST.get('soil_type')
        # For simplicity, farm is expected as an ID or name; adjust as needed
        farm_obj = Farm.objects.filter(name=farm).first() if farm else None
        Field.objects.create(name=name, purpose=purpose, farm=farm_obj, total_size=total_size, size_unit=size_unit, soil_type=soil_type)
        return redirect('field_list')
    return render(request, 'fields/field_form.html')

def field_update(request, pk):
    field = get_object_or_404(Field, pk=pk)
    if request.method == 'POST':
        field.name = request.POST.get('name')
        field.purpose = request.POST.get('purpose')
        farm = request.POST.get('farm')
        field.total_size = request.POST.get('total_size')
        field.size_unit = request.POST.get('size_unit')
        field.soil_type = request.POST.get('soil_type')
        field.farm = Farm.objects.filter(name=farm).first() if farm else None
        field.save()
        return redirect('field_list')
    return render(request, 'fields/field_form.html', {'field': field})

def field_delete(request, pk):
    field = get_object_or_404(Field, pk=pk)
    if request.method == 'POST':
        field.delete()
        return redirect('field_list')
    return render(request, 'fields/field_confirm_delete.html', {'field': field})
