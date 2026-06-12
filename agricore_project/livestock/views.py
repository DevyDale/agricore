def animal_create(request):
    if request.method == 'POST':
        tag_id = request.POST.get('tag_id')
        name = request.POST.get('name')
        sex = request.POST.get('sex')
        age_group = request.POST.get('age_group')
        breed = request.POST.get('breed')
        status = request.POST.get('status')
        unit_id = request.POST.get('livestock_unit')
        livestock_unit = LivestockUnit.objects.get(id=unit_id) if unit_id else None
        Animal.objects.create(
            tag_id=tag_id,
            name=name,
            sex=sex,
            age_group=age_group,
            breed=breed,
            status=status,
            livestock_unit=livestock_unit
        )
        return redirect('livestock:livestock_list')
    units = LivestockUnit.objects.all()
    return render(request, 'livestock/animal_form.html', {'units': units})
from django.shortcuts import render, get_object_or_404, redirect
def livestock_dashboard(request):
    animals = Animal.objects.select_related('livestock_unit').all()
    units = LivestockUnit.objects.all()
    if request.method == 'POST':
        tag_id = request.POST.get('tag_id')
        name = request.POST.get('name')
        sex = request.POST.get('sex')
        age_group = request.POST.get('age_group')
        breed = request.POST.get('breed')
        status = request.POST.get('status')
        unit_id = request.POST.get('livestock_unit')
        livestock_unit = LivestockUnit.objects.get(id=unit_id) if unit_id else None
        Animal.objects.create(
            tag_id=tag_id,
            name=name,
            sex=sex,
            age_group=age_group,
            breed=breed,
            status=status,
            livestock_unit=livestock_unit
        )
        return redirect('livestock:livestock_dashboard')
    return render(request, 'livestock.html', {'animals': animals, 'units': units})
from .models import Animal, LivestockUnit
from django.urls import reverse

def livestock_list(request):
    animals = Animal.objects.select_related('livestock_unit').all()
    units = LivestockUnit.objects.all()
    return render(request, 'livestock/livestock_list.html', {'animals': animals, 'units': units})

def livestock_create(request):
    if request.method == 'POST':
        tag_id = request.POST.get('tag_id')
        name = request.POST.get('name')
        sex = request.POST.get('sex')
        age_group = request.POST.get('age_group')
        breed = request.POST.get('breed')
        status = request.POST.get('status')
        unit_id = request.POST.get('livestock_unit')
        livestock_unit = LivestockUnit.objects.get(id=unit_id) if unit_id else None
        Animal.objects.create(
            tag_id=tag_id,
            name=name,
            sex=sex,
            age_group=age_group,
            breed=breed,
            status=status,
            livestock_unit=livestock_unit
        )
        return redirect('livestock_list')
    units = LivestockUnit.objects.all()
    return render(request, 'livestock/livestock_form.html', {'units': units})

def livestock_update(request, pk):
    animal = get_object_or_404(Animal, pk=pk)
    if request.method == 'POST':
        animal.tag_id = request.POST.get('tag_id')
        animal.name = request.POST.get('name')
        animal.sex = request.POST.get('sex')
        animal.age_group = request.POST.get('age_group')
        animal.breed = request.POST.get('breed')
        animal.status = request.POST.get('status')
        unit_id = request.POST.get('livestock_unit')
        animal.livestock_unit = LivestockUnit.objects.get(id=unit_id) if unit_id else None
        animal.save()
        return redirect('livestock_list')
    units = LivestockUnit.objects.all()
    return render(request, 'livestock/livestock_form.html', {'animal': animal, 'units': units})

def livestock_delete(request, pk):
    animal = get_object_or_404(Animal, pk=pk)
    if request.method == 'POST':
        animal.delete()
        return redirect('livestock_list')
    return render(request, 'livestock/livestock_confirm_delete.html', {'animal': animal})
