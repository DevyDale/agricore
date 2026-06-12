from django.contrib.auth import authenticate, login
from django.shortcuts import redirect
def login_view(request):
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')
        user = authenticate(request, username=username, password=password)
        if user is not None:
            login(request, user)
            next_url = request.GET.get('next', '/')
            return redirect(next_url)
        else:
            return render(request, 'accounts/login.html', {'error': 'Invalid credentials'})
    return render(request, 'accounts/login.html')
from django.shortcuts import render

def authentication_view(request):
    return render(request, 'authentication.html')

def cart_view(request):
    return render(request, 'cart.html')

def chat_detail_view(request):
    return render(request, 'chat_detail.html')

def chats_view(request):
    return render(request, 'chats.html')

def digital_store_view(request):
    return render(request, 'digital_store.html')

def digitalstores_view(request):
    return render(request, 'digitalstores.html')

def individual_farm_view(request):
    return render(request, 'individual_farm.html')

def marketplace_view(request):
    return render(request, 'marketplace.html')

def multi_farm_view(request):
    return render(request, 'multi_farm.html')

def onboarding_view(request):
    return render(request, 'onboarding.html')

def product_detail_view(request):
    return render(request, 'product_detail.html')

def profile_view(request):
    return render(request, 'profile.html')

def splashscreen_view(request):
    return render(request, 'splashscreen.html')

def workforce_view(request):
    return render(request, 'workforce.html')
