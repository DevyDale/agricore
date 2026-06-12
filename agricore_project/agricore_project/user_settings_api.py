from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
import json

@csrf_exempt
def user_settings(request):
    if request.method == 'POST':
        data = json.loads(request.body)
        request.session['user_settings'] = data
        return JsonResponse({'status': 'ok'})
    elif request.method == 'GET':
        settings = request.session.get('user_settings', {})
        return JsonResponse(settings)
