import requests


class CerebrasClient:
    """Minimal OpenAI-compatible client for Cerebras (CerebrasCloud).

    .chat() returns the same shape Dale already expects:
        {"choices": [{"message": {"content": ...}}], "usage": {"total_tokens": n}}
    On any error it returns a friendly "(Dale tripped on a wire - ...)" message
    instead of raising, so the chat endpoint never 500s on a provider hiccup.
    """

    ENDPOINT = "https://api.cerebras.ai/v1/chat/completions"

    def __init__(self, api_key, model="llama-3.3-70b-versatile"):
        self.api_key = api_key
        self.model = model

    def chat(self, messages, model=None, temperature=0.2, max_tokens=700):
        if not self.api_key:
            return self._fallback("CEREBRAS_API_KEY is not set")
        chosen = model or self.model
        payload = {
            "model": chosen,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        # gpt-oss models are reasoning models; keep effort low so chat stays fast
        # and the final answer isn't crowded out of the token budget.
        if "gpt-oss" in (chosen or "").lower():
            payload["reasoning_effort"] = "low"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        try:
            resp = requests.post(self.ENDPOINT, json=payload, headers=headers, timeout=60)
        except requests.RequestException as e:
            return self._fallback(str(e))
        if resp.status_code != 200:
            try:
                err = resp.json().get("error", {}).get("message") or resp.text[:300]
            except Exception:
                err = resp.text[:300]
            return self._fallback(err)
        try:
            return resp.json()
        except Exception as e:
            return self._fallback(f"bad response: {e}")

    @staticmethod
    def _fallback(msg):
        return {
            "choices": [{"message": {"content": f"(Dale tripped on a wire - {msg}..)"}}],
            "usage": {"total_tokens": 0},
        }
