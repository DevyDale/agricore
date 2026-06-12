from rest_framework import viewsets, status
from drf_spectacular.utils import extend_schema, inline_serializer, OpenApiResponse
from rest_framework import serializers
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView
from rest_framework.response import Response
from django.conf import settings
from .gemini_client import GeminiClient
from .cerebras_client import CerebrasClient
from rest_framework.parsers import MultiPartParser, FormParser
import json
import re
from datetime import datetime
from ai.models import AILog, Alert
from .serializers import AILogSerializer, AlertSerializer

class AILogViewSet(viewsets.ModelViewSet):
    queryset = AILog.objects.all()
    serializer_class = AILogSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)



class AlertViewSet(viewsets.ModelViewSet):
    queryset = Alert.objects.all()
    serializer_class = AlertSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(farm__owner=self.request.user)


class DaleAIChatView(APIView):
            # Friendly greeting detection (let Llama/Ollama handle)
            # If the prompt matches a greeting, do not return a hardcoded response—let the LLM generate a reply using context and user data.
    permission_classes = [IsAuthenticated]

    @extend_schema(request=inline_serializer(name="DaleAskRequest", fields={"prompt": serializers.CharField(), "context": serializers.JSONField(required=False), "history": serializers.JSONField(required=False)}), responses=inline_serializer(name="DaleAskResponse", fields={"reply": serializers.CharField(), "log_id": serializers.IntegerField(), "action": serializers.JSONField()}))
    def post(self, request):
        import re
        """
        Enhanced Dale AI chat endpoint for marketplace/digital_store context.
        Body: { prompt: str, context: {type, id, page, extras}, history: optional [ {role, content} ] }
        Returns: { reply: str, log_id: int, action: {type, ...} }
        """
        from marketplace.models import Product
        data = request.data or {}
        prompt = data.get('prompt', '').strip()
        if not prompt:
            return Response({'detail': 'prompt is required'}, status=status.HTTP_400_BAD_REQUEST)

        context = data.get('context') or {}
        history = data.get('history') or []
        # Extract context_type, context_id, and page for use below
        context_type = context.get('type')
        context_id = context.get('id')
        page = context.get('page')
        extras = context.get('extras')

        # Dynamic system prompt logic for all major pages
        page_name = (page or '').lower() if page else ''
        if 'multi_farm' in page_name or 'farms' in page_name or 'dashboard' in page_name:
            system_msg = (
                "You are Dale AI, a context-aware assistant for the Multi-Farm Dashboard. "
                "Help users understand their farms, avoid mistakes when adding new farms, and decide what to do next using ONLY the data already on the screen. "
                "Never hallucinate or invent data. Do not answer unrelated questions. "
                "Explain what the user is seeing, summarize farm cards, help with the Add New Farm form, explain errors, guide actions, and suggest next steps. "
                "If the user is in demo mode, explain that. Be friendly, concise, and always reference the actual farm data and UI state."
            )
        elif 'marketplace' in page_name:
            system_msg = (
                "You are Dale AI, a context-aware assistant for the Marketplace page. "
                "Help users understand the page state, summarize farm data, assist with adding farms, explain errors, guide actions, and suggest next steps using ONLY the data on the page. "
                "Never hallucinate or answer unrelated questions."
            )
        elif 'digital_store' in page_name or 'digitalstores' in page_name:
            system_msg = (
                "You are Dale AI, a context-aware assistant for the Digital Store page. "
                "Help users understand farm cards, loading/empty/error states, summarize farms, help with the Add New Farm form, explain errors, guide actions, and suggest next steps using ONLY the data on the screen. "
                "Never hallucinate or answer unrelated questions."
            )
        elif 'chats' in page_name:
            system_msg = (
                "You are Dale AI, a context-aware assistant for the Chats page. "
                "Explain what the farms list means, why it’s empty/loading/error, summarize farms, help with adding a new farm, explain why something isn’t working, guide page actions, and suggest next steps using ONLY the data on the page. "
                "Never hallucinate or answer unrelated questions."
            )
        elif 'workforce' in page_name:
            system_msg = (
                "You are Dale AI, a context-aware assistant for the Workforce page. "
                "Help users understand the workforce list, guide filtering and actions, and suggest the top professionals based on ratings and reviews using ONLY the data already on the page. "
                "Never hallucinate or answer unrelated questions."
            )
        else:
            system_msg = (
                "You are Dale AI, a context-aware assistant for the Agricore platform. "
                "Help users understand, manage, and improve their data using ONLY the context provided. Never hallucinate or answer unrelated questions."
            )

        # --- Only use hardcoded/context answers for strict, data-only queries (e.g. farm count, direct list, etc.) ---
        farms = context.get('farms') if isinstance(context.get('farms'), list) else []
        reply = None
        # Only intercept for strict, data-only queries
        if farms and re.fullmatch(r'(how many|number of|count|total) farms?', prompt.strip().lower()):
            farm_count = len(farms)
            reply = f'You have {farm_count} farm{"s" if farm_count != 1 else ""}.'
            resp = {'reply': reply, 'log_id': None}
            return Response(resp)
        farms = context.get('farms') if isinstance(context.get('farms'), list) else []
        # Handle 'how many farms' and similar questions
        if farms and re.search(r'(how many|number of|count|list|show|summarize|which|what|group|largest|smallest|total|all).*farm', prompt, re.I):
            farm_count = len(farms)
            if re.search(r'(how many|number of|count|total).*farm', prompt, re.I):
                reply = f'You have {farm_count} farm{"s" if farm_count != 1 else ""}.'
            elif re.search(r'list|show|all.*farm', prompt, re.I):
                names = ', '.join(f.get('name', 'Unnamed') for f in farms)
                reply = f'Your farms: {names}' if names else 'You have no farms.'
            elif re.search(r'largest', prompt, re.I):
                largest = max(farms, key=lambda f: f.get('total_size', 0), default=None)
                if largest:
                    reply = f'Your largest farm is {largest.get("name", "Unnamed")} ({largest.get("total_size", "?")} acres).'
                else:
                    reply = 'No farm size data available.'
            elif re.search(r'smallest', prompt, re.I):
                smallest = min(farms, key=lambda f: f.get('total_size', 0), default=None)
                if smallest:
                    reply = f'Your smallest farm is {smallest.get("name", "Unnamed")} ({smallest.get("total_size", "?")} acres).'
                else:
                    reply = 'No farm size data available.'
            elif re.search(r'group.*type', prompt, re.I):
                from collections import Counter
                types = [f.get('type', 'Unknown') for f in farms]
                counts = Counter(types)
                reply = 'Farms by type: ' + ', '.join(f'{k}: {v}' for k, v in counts.items())
            elif re.search(r'which.*livestock', prompt, re.I):
                livestock = [f.get('name', 'Unnamed') for f in farms if f.get('type') == 'livestock']
                reply = 'Livestock farms: ' + ', '.join(livestock) if livestock else 'You have no livestock farms.'
            elif re.search(r'which.*crop', prompt, re.I):
                crop = [f.get('name', 'Unnamed') for f in farms if f.get('type') == 'crops']
                reply = 'Crop farms: ' + ', '.join(crop) if crop else 'You have no crop farms.'
            elif re.search(r'which.*mixed', prompt, re.I):
                    if 'multi_farm' in page_name or 'farms' in page_name or 'dashboard' in page_name:
                        system_msg = (
                            "You are Dale AI, a context-aware assistant for the Multi-Farm Dashboard. "
                            "Guide users step-by-step through the page, describing each feature and how to use it. "
                            "As you mention a feature (like a button, card, or form), include a clear highlight instruction in your reply, e.g. 'Highlight the Add Farm button' or 'Focus on the farm card'. "
                            "Help users understand their farms, avoid mistakes when adding new farms, and decide what to do next using ONLY the data already on the screen. "
                            "Never hallucinate or invent data. Do not answer unrelated questions. "
                            "Explain what the user is seeing, summarize farm cards, help with the Add New Farm form, explain errors, guide actions, and suggest next steps. "
                            "If the user is in demo mode, explain that. Be friendly, concise, and always reference the actual farm data and UI state."
                        )
                    reply = f'Farms under {limit}: ' + ', '.join(under) if under else f'No farms under {limit}.'
            # Add more context Q&A as needed
            if reply:
                resp = {'reply': reply, 'log_id': None}
                return Response(resp)

        messages = [{'role': 'system', 'content': system_msg}]

        # Ground the assistant in real platform data (prices, buyers, transport, produce).
        # Wrapped so a data hiccup can never break the chat.
        try:
            from .agri_tools import build_grounding
            grounding = build_grounding(request.user, prompt, context)
            if grounding:
                messages.append({'role': 'system', 'content': grounding})
        except Exception:
            pass

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

        # --- All open-ended, conversational, and greeting prompts go to the LLM (Mistral) ---
        # Only use context-only answers for strict fact queries (see above)
        action = None

        client = CerebrasClient(getattr(settings, 'CEREBRAS_API_KEY', ''), getattr(settings, 'CEREBRAS_MODEL', 'gpt-oss-120b'))
        try:
            completion = client.chat(
                messages=messages,
                model=getattr(settings, 'CEREBRAS_MODEL', 'gpt-oss-120b'),
                temperature=0.2,
                max_tokens=700,
            )
            ai_reply = completion["choices"][0]["message"]["content"] if completion.get("choices") else ''
            tokens_used = completion.get("usage", {}).get("total_tokens", 0)
            if not reply:
                reply = ai_reply
        except Exception as e:
            return Response({'detail': f'AI error: {e}'}, status=status.HTTP_502_BAD_GATEWAY)

        log = AILog.objects.create(
            user=request.user,
            context_type=page or context_type,
            context_id=context_id or 0,
            prompt=prompt,
            response=reply,
            model=getattr(settings, 'CEREBRAS_MODEL', 'gpt-oss-120b'),
            tokens_used=tokens_used or 0,
        )

        resp = {'reply': reply, 'log_id': log.id}
        if action:
            resp['action'] = action
        return Response(resp)


# ---------------------------------------------------------------------------
# Crop disease diagnosis from a photo (Gemini vision)
# ---------------------------------------------------------------------------
DIAGNOSIS_SYSTEM = (
    "You are Dale, a crop health assistant for African smallholder farmers. "
    "Examine the plant photo and identify the most likely disease, pest, or "
    "nutrient deficiency. Respond ONLY with a JSON object (no markdown, no code "
    "fences) using exactly these keys: "
    "crop (string - your best guess of the crop), "
    "diagnosis (string - the single most likely problem), "
    "confidence (string - one of: low, medium, high), "
    "severity (string - one of: low, medium, high), "
    "symptoms (array of short strings describing what you see), "
    "treatment (array of short practical steps suited to a smallholder farmer), "
    "consult_expert (boolean), "
    "note (string - one short caveat). "
    "If the image is not a plant or is too unclear to assess, set diagnosis to "
    "Unable to assess and explain why in note. For any serious or uncertain case "
    "set consult_expert to true and advise confirming with a local agricultural "
    "officer before applying chemicals."
)

_ALLOWED_IMAGE_TYPES = {
    "image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic", "image/heif",
}


def _extract_json(text):
    """Pull a JSON object out of the model reply; return dict or None."""
    if not text:
        return None
    t = text.strip()
    t = re.sub(r"^```(?:json)?", "", t).strip()
    t = re.sub(r"```$", "", t).strip()
    start, end = t.find("{"), t.rfind("}")
    if start != -1 and end != -1 and end > start:
        t = t[start:end + 1]
    try:
        return json.loads(t)
    except Exception:
        return None


class CropDiagnosisView(APIView):
    """POST an image (form field 'image') of a crop; returns a structured diagnosis."""
    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    @extend_schema(request={"multipart/form-data": inline_serializer(name="CropDiagnoseRequest", fields={"image": serializers.ImageField(), "prompt": serializers.CharField(required=False), "crop": serializers.CharField(required=False)})}, responses=OpenApiResponse(description="Structured crop diagnosis (JSON)."))
    def post(self, request):
        image = request.FILES.get("image")
        if not image:
            return Response({"detail": "An image file is required (form field 'image')."},
                            status=status.HTTP_400_BAD_REQUEST)

        content_type = (getattr(image, "content_type", "") or "").lower()
        if content_type not in _ALLOWED_IMAGE_TYPES:
            return Response({"detail": f"Unsupported image type: {content_type or 'unknown'}."},
                            status=status.HTTP_400_BAD_REQUEST)
        if getattr(image, "size", 0) and image.size > 8 * 1024 * 1024:
            return Response({"detail": "Image too large (max 8MB)."},
                            status=status.HTTP_400_BAD_REQUEST)

        prompt = (request.data.get("prompt") or "").strip() or "What is wrong with this crop?"
        crop_hint = (request.data.get("crop") or "").strip()
        if crop_hint:
            prompt = f"The farmer says this is {crop_hint}. {prompt}"

        client = GeminiClient(
            api_key=getattr(settings, "GEMINI_API_KEY", ""),
            model=getattr(settings, "GEMINI_MODEL", "gemini-2.0-flash"),
        )
        mime = "image/jpeg" if content_type in ("image/jpg", "image/jpeg") else content_type
        result = client.vision(
            prompt=prompt,
            image_bytes=image.read(),
            mime_type=mime,
            system_text=DIAGNOSIS_SYSTEM,
        )
        text = result["choices"][0]["message"]["content"]
        tokens = result.get("usage", {}).get("total_tokens", 0)
        diagnosis = _extract_json(text)

        try:
            AILog.objects.create(
                user=request.user,
                context_type="crop_diagnosis",
                context_id=0,
                prompt=prompt,
                response=text,
                model=getattr(settings, "GEMINI_MODEL", "gemini-2.0-flash"),
                tokens_used=tokens or 0,
            )
        except Exception:
            pass

        return Response({"diagnosis": diagnosis, "raw": text})
