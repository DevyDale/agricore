import requests

class OllamaClient:
    def __init__(self, base_url="http://localhost:11434/v1/chat/completions"):
        self.base_url = base_url

    def chat(self, messages, model="llama3", temperature=0.2, max_tokens=700):
        data = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        response = requests.post(self.base_url, json=data)
        response.raise_for_status()
        return response.json()
