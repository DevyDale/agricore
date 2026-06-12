"""
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
                merged[-1] = (role, merged[-1][1] + "\n" + text)
            else:
                merged.append((role, text))
        while merged and merged[0][0] != "user":
            merged.pop(0)
        if not merged:
            merged = [("user", "Say hi and offer help. Keep it short.")]
        contents = [{"role": r, "parts": [{"text": t}]} for r, t in merged]
        return "\n\n".join(system_parts), contents


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
