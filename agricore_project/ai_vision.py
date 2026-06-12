#!/usr/bin/env python3
"""
Land the hosted AI brain + crop-disease vision in one step.

  * Creates ai/api/gemini_client.py  (text chat() + image vision()).
  * settings.py: GEMINI_API_KEY, GEMINI_MODEL.
  * ai/api/views.py: swap the chat from local Ollama -> Gemini, and add
    CropDiagnosisView (upload a crop photo -> structured disease diagnosis).
  * urls.py: POST /api/ai/diagnose-crop/

Run from the directory containing manage.py:
    python ai_vision.py
Then add GEMINI_API_KEY to .env (reuse your TCS key).
"""
import os
import sys
import shutil
from datetime import datetime

BACKUP = ".backend_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S")

GEMINI_CLIENT = '''"""
Gemini client for Dale AI: text chat + image (vision) diagnosis.

Drop-in for the old OllamaClient - same .chat(messages=...) signature and
OpenAI-style return shape - plus .vision() for crop-photo analysis. Hosted via
Google Gemini generateContent (no local server). Adapted from the TCS engine.
"""
import base64
import requests

ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

_SAFETY = [
    {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_ONLY_HIGH"},
    {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_ONLY_HIGH"},
    {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
    {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_ONLY_HIGH"},
]


class GeminiClient:
    def __init__(self, api_key="", model="gemini-2.0-flash"):
        self.api_key = api_key
        self.model = model or "gemini-2.0-flash"

    def chat(self, messages, model=None, temperature=0.2, max_tokens=700):
        model = self._model(model)
        if not self.api_key:
            return _wrap("(AI isn't configured yet - set GEMINI_API_KEY in the environment.)")
        system_text, contents = self._convert(messages)
        body = {
            "contents": contents,
            "generationConfig": {"temperature": temperature, "maxOutputTokens": max_tokens, "topP": 0.95},
            "safetySettings": _SAFETY,
        }
        if system_text:
            body["system_instruction"] = {"parts": [{"text": system_text}]}
        return self._send(model, body)

    def vision(self, prompt, image_bytes, mime_type="image/jpeg", system_text=None,
               model=None, temperature=0.4, max_tokens=800):
        model = self._model(model)
        if not self.api_key:
            return _wrap("(AI isn't configured yet - set GEMINI_API_KEY in the environment.)")
        b64 = base64.b64encode(image_bytes).decode("ascii")
        parts = [
            {"text": prompt or "Diagnose any disease, pest or deficiency visible in this crop photo."},
            {"inline_data": {"mime_type": mime_type, "data": b64}},
        ]
        body = {
            "contents": [{"role": "user", "parts": parts}],
            "generationConfig": {"temperature": temperature, "maxOutputTokens": max_tokens, "topP": 0.95},
            "safetySettings": _SAFETY,
        }
        if system_text:
            body["system_instruction"] = {"parts": [{"text": system_text}]}
        return self._send(model, body)

    def _model(self, model):
        model = model or self.model
        return model if str(model).startswith("gemini") else self.model

    def _send(self, model, body):
        try:
            r = requests.post(
                ENDPOINT.format(model=model),
                params={"key": self.api_key},
                json=body,
                timeout=45,
            )
            r.raise_for_status()
            data = r.json()
        except requests.HTTPError as e:
            return _wrap(f"(Dale tripped on a wire - {_http_err(e)}.)")
        except requests.RequestException:
            return _wrap("(Dale couldn't reach the network just now. Try again in a moment.)")
        except Exception as e:
            return _wrap(f"(Dale ran into an error: {e})")
        return _parse(data)

    @staticmethod
    def _convert(messages):
        system_parts, raw = [], []
        for m in messages or []:
            text = str(m.get("content", "")).strip()
            if not text:
                continue
            role = m.get("role")
            if role == "system":
                system_parts.append(text)
            elif role == "assistant":
                raw.append(("model", text))
            else:
                raw.append(("user", text))
        merged = []
        for role, text in raw:
            if merged and merged[-1][0] == role:
                merged[-1] = (role, merged[-1][1] + "\\n" + text)
            else:
                merged.append((role, text))
        while merged and merged[0][0] != "user":
            merged.pop(0)
        if not merged:
            merged = [("user", "Say hi and offer help. Keep it short.")]
        contents = [{"role": r, "parts": [{"text": t}]} for r, t in merged]
        return "\\n\\n".join(system_parts), contents


def _parse(data):
    candidates = data.get("candidates") or []
    if not candidates:
        reason = (data.get("promptFeedback") or {}).get("blockReason")
        if reason:
            return _wrap(f"(Dale couldn't respond - content blocked: {reason}.)")
        return _wrap("(Dale didn't have a reply for that one.)")
    parts = (candidates[0].get("content") or {}).get("parts") or []
    text = "".join(p.get("text", "") for p in parts).strip()
    tokens = (data.get("usageMetadata") or {}).get("totalTokenCount", 0)
    return _wrap(text or "(Dale didn't have a reply for that one.)", tokens)


def _http_err(e):
    try:
        return e.response.json().get("error", {}).get("message", f"HTTP {e.response.status_code}")
    except Exception:
        return f"HTTP {getattr(e.response, 'status_code', '?')}"


def _wrap(text, tokens=0):
    return {"choices": [{"message": {"content": text}}], "usage": {"total_tokens": tokens}}
'''

# ---- views.py: code appended at end of file (crop diagnosis) ---------------
VIEW_APPEND = '''


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
'''

SET_OLD = "OLLAMA_BASE_URL = env('OLLAMA_BASE_URL', default='http://localhost:11434/v1/chat/completions')"
SET_NEW = (
    "OLLAMA_BASE_URL = env('OLLAMA_BASE_URL', default='http://localhost:11434/v1/chat/completions')\n"
    "GEMINI_API_KEY = env('GEMINI_API_KEY', default='')\n"
    "GEMINI_MODEL = env('GEMINI_MODEL', default='gemini-2.0-flash')"
)

VIEW_EDITS = [
    (
        "from .ollama_client import OllamaClient",
        ("from .gemini_client import GeminiClient\n"
         "from rest_framework.parsers import MultiPartParser, FormParser\n"
         "import json\n"
         "import re"),
    ),
    (
        "        client = OllamaClient(base_url=getattr(settings, 'OLLAMA_BASE_URL', 'http://localhost:11434/v1/chat/completions'))",
        "        client = GeminiClient(api_key=getattr(settings, 'GEMINI_API_KEY', ''), model=getattr(settings, 'GEMINI_MODEL', 'gemini-2.0-flash'))",
    ),
    (
        """            completion = client.chat(
                messages=messages,
                model=getattr(settings, 'OLLAMA_MODEL', 'llama3'),
                temperature=0.2,
                max_tokens=700,
            )""",
        """            completion = client.chat(
                messages=messages,
                model=getattr(settings, 'GEMINI_MODEL', 'gemini-2.0-flash'),
                temperature=0.2,
                max_tokens=700,
            )""",
    ),
    (
        """            prompt=prompt,
            response=reply,
            model=getattr(settings, 'OLLAMA_MODEL', 'llama3'),
            tokens_used=tokens_used or 0,""",
        """            prompt=prompt,
            response=reply,
            model=getattr(settings, 'GEMINI_MODEL', 'gemini-2.0-flash'),
            tokens_used=tokens_used or 0,""",
    ),
]

URL_IMPORT_OLD = """from ai.api.views import (
    AILogViewSet,
    AlertViewSet,
    DaleAIChatView,
)"""
URL_IMPORT_NEW = """from ai.api.views import (
    AILogViewSet,
    AlertViewSet,
    DaleAIChatView,
    CropDiagnosisView,
)"""

URL_PATH_OLD = "    path('api/ai/dale/ask/', DaleAIChatView.as_view(), name='dale_ai_ask'),"
URL_PATH_NEW = (
    "    path('api/ai/dale/ask/', DaleAIChatView.as_view(), name='dale_ai_ask'),\n"
    "    path('api/ai/diagnose-crop/', CropDiagnosisView.as_view(), name='crop_diagnosis'),"
)


def main():
    if not os.path.exists("manage.py"):
        sys.exit("ERROR: run from the directory containing manage.py (agricore_project/).")

    settings_p = "agricore_project/settings.py"
    views_p = "ai/api/views.py"
    urls_p = "agricore_project/urls.py"
    for p in (settings_p, views_p, urls_p):
        if not os.path.exists(p):
            sys.exit(f"ERROR: missing {p}")

    with open(settings_p, encoding="utf-8") as f:
        s = f.read()
    with open(views_p, encoding="utf-8") as f:
        v = f.read()
    with open(urls_p, encoding="utf-8") as f:
        u = f.read()

    problems = []
    if "GEMINI_API_KEY" in s:
        problems.append("settings.py already has GEMINI_API_KEY")
    if s.count(SET_OLD) != 1:
        problems.append("settings.py OLLAMA_BASE_URL anchor not found once")
    if "CropDiagnosisView" in v:
        problems.append("views.py already has CropDiagnosisView")
    for old, _new in VIEW_EDITS:
        if v.count(old) != 1:
            problems.append(f"views.py anchor not found once: {old.strip()[:48]}")
    if u.count(URL_IMPORT_OLD) != 1:
        problems.append("urls.py import block anchor not found once")
    if u.count(URL_PATH_OLD) != 1:
        problems.append("urls.py dale path anchor not found once")
    if problems:
        print("Aborting - code didn't match expected:")
        for p in problems:
            print("  -", p)
        sys.exit(1)

    os.makedirs(BACKUP, exist_ok=True)
    for p in (settings_p, views_p, urls_p):
        dest = os.path.join(BACKUP, p)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy2(p, dest)

    with open("ai/api/gemini_client.py", "w", encoding="utf-8") as f:
        f.write(GEMINI_CLIENT)
    print("  [new]  ai/api/gemini_client.py (chat + vision)")

    s = s.replace(SET_OLD, SET_NEW, 1)
    with open(settings_p, "w", encoding="utf-8") as f:
        f.write(s)
    print("  [edit] settings.py (GEMINI keys)")

    for old, new in VIEW_EDITS:
        v = v.replace(old, new, 1)
    v = v + VIEW_APPEND
    with open(views_p, "w", encoding="utf-8") as f:
        f.write(v)
    print("  [edit] ai/api/views.py (Gemini swap + CropDiagnosisView)")

    u = u.replace(URL_IMPORT_OLD, URL_IMPORT_NEW, 1).replace(URL_PATH_OLD, URL_PATH_NEW, 1)
    with open(urls_p, "w", encoding="utf-8") as f:
        f.write(u)
    print("  [edit] urls.py (POST /api/ai/diagnose-crop/)")

    print(f"\nDone. Backups in {BACKUP}/")
    print("Add GEMINI_API_KEY to .env (reuse your TCS key).")


if __name__ == "__main__":
    main()
