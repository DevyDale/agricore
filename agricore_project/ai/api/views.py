from rest_framework import viewsets, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView
from rest_framework.response import Response
from django.conf import settings
from groq import Groq
from datetime import datetime
from ai.models import AILog, Prediction, Alert
from .serializers import AILogSerializer, PredictionSerializer, AlertSerializer

class AILogViewSet(viewsets.ModelViewSet):
    queryset = AILog.objects.all()
    serializer_class = AILogSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

class PredictionViewSet(viewsets.ModelViewSet):
    queryset = Prediction.objects.all()
    serializer_class = PredictionSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)

class AlertViewSet(viewsets.ModelViewSet):
    queryset = Alert.objects.all()
    serializer_class = AlertSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)


class DaleAIChatView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        """
        Generic chat endpoint for Dale AI.
        Body: { prompt: str, context: {type, id, page, extras}, history: optional [ {role, content} ] }
        Returns: { reply: str, log_id: int }
        """
        data = request.data or {}
        prompt = data.get('prompt', '').strip()
        if not prompt:
            return Response({'detail': 'prompt is required'}, status=status.HTTP_400_BAD_REQUEST)

        context = data.get('context') or {}
        history = data.get('history') or []

        # Build system/context message
        page = context.get('page') or request.headers.get('X-Page-Context') or ''
        context_type = context.get('type') or 'generic'
        context_id = context.get('id')
        extras = context.get('extras') or {}

        system_msg = (
            "You are Dale AI, an assistant for the Agricore platform. "
            "Be concise, actionable, and context-aware. "
            "Only assist the authenticated user. If asked about recommendations, justify with ratings/reviews data provided in 'extras' when available."
        )

        messages = [{'role': 'system', 'content': system_msg}]

        # Thread a short memory from last 5 logs for this user and page
        recent = (
            AILog.objects.filter(user=request.user, context_type=page or context_type)
            .order_by('-created_at')[:5]
        )
        for item in reversed(list(recent)):
            messages.append({'role': 'user', 'content': item.prompt[:4000]})
            messages.append({'role': 'assistant', 'content': item.response[:4000]})

        for h in history[-6:]:  # include up to last 6 turns from client
            if 'role' in h and 'content' in h:
                messages.append({'role': h['role'], 'content': str(h['content'])[:6000]})

        if extras:
            messages.append({'role': 'system', 'content': f"Context extras (JSON): {extras}"})

        messages.append({'role': 'user', 'content': prompt})

        client = Groq(api_key=getattr(settings, 'GROQ_API_KEY', ''))
        try:
            # Use a compact, fast model for responsiveness
            completion = client.chat.completions.create(
                model='llama3-8b-8192',
                messages=messages,
                temperature=0.2,
                max_tokens=700,
            )
            reply = completion.choices[0].message.content if completion.choices else ''
            usage = getattr(completion, 'usage', None)
            tokens_used = getattr(usage, 'total_tokens', 0) if usage else 0
        except Exception as e:
            return Response({'detail': f'AI error: {e}'}, status=status.HTTP_502_BAD_GATEWAY)

        log = AILog.objects.create(
            user=request.user,
            context_type=page or context_type,
            context_id=context_id or 0,
            prompt=prompt,
            response=reply,
            model='llama3-8b-8192',
            tokens_used=tokens_used or 0,
        )

        return Response({'reply': reply, 'log_id': log.id})