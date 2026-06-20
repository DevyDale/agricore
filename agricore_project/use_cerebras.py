#!/usr/bin/env python
"""
use_cerebras.py  —  Point Dale's chat at Cerebras (you already have a working Cerebras key).

Run from the folder that contains manage.py:

    python use_cerebras.py

What it does (all idempotent, with backups):
  1. Creates ai/api/cerebras_client.py  (OpenAI-compatible Cerebras client, same return shape Dale expects).
  2. Edits ai/api/views.py:
        - adds `from .cerebras_client import CerebrasClient` (keeps the Gemini import so the
          crop-photo view still loads),
        - swaps ONLY the chat view's LLM client to CerebrasClient,
        - points its model setting at CEREBRAS_MODEL.
  3. Adds CEREBRAS_API_KEY / CEREBRAS_MODEL to settings.py (reads them from your .env).

Nothing about the crop-disease (vision) path is removed — it just stays on Gemini,
ready for whenever you have a valid AIza key.
"""
import os
import re
import sys
import shutil
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))

VIEWS = os.path.join(HERE, "ai", "api", "views.py")
CEREBRAS_CLIENT = os.path.join(HERE, "ai", "api", "cerebras_client.py")

# settings.py lives at <project>/<project>/settings.py
SETTINGS = None
for root, _dirs, files in os.walk(HERE):
    if "settings.py" in files and os.path.basename(root) == "agricore_project":
        SETTINGS = os.path.join(root, "settings.py")
        break
if SETTINGS is None:
    # fallback: any settings.py with DJANGO markers
    for root, _dirs, files in os.walk(HERE):
        if "settings.py" in files:
            p = os.path.join(root, "settings.py")
            if "INSTALLED_APPS" in open(p, encoding="utf-8").read():
                SETTINGS = p
                break

STAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
BACKUP_DIR = os.path.join(HERE, f".cerebras_backup_{STAMP}")


def die(msg):
    print(f"\n[ABORT] {msg}")
    print("No files were changed (or backups are in the backup dir). Nothing broken.")
    sys.exit(1)


def backup(path):
    if not os.path.exists(BACKUP_DIR):
        os.makedirs(BACKUP_DIR)
    rel = os.path.relpath(path, HERE).replace(os.sep, "__")
    shutil.copy2(path, os.path.join(BACKUP_DIR, rel))


CEREBRAS_CLIENT_SRC = '''import requests


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
'''

CEREBRAS_DEFAULT_MODEL = "gpt-oss-120b"


def patch_views(text):
    changes = []

    # 1) Ensure the Cerebras import exists, keeping any existing gemini/ollama import.
    if "from .cerebras_client import CerebrasClient" not in text:
        new_text, n = re.subn(
            r"(from \.\w*client import \w+Client\n)",
            r"\1from .cerebras_client import CerebrasClient\n",
            text,
            count=1,
        )
        if n == 0:
            die("Could not find the AI client import line in ai/api/views.py.")
        text = new_text
        changes.append("added CerebrasClient import")
    else:
        changes.append("CerebrasClient import already present")

    # 2) Swap ONLY the chat view's client instantiation (first `client = XxxClient(...)`).
    new_text, n = re.subn(
        r"client = \w+Client\([^\n]*\)",
        "client = CerebrasClient(getattr(settings, 'CEREBRAS_API_KEY', ''), "
        "getattr(settings, 'CEREBRAS_MODEL', '%s'))" % CEREBRAS_DEFAULT_MODEL,
        text,
        count=1,
    )
    if n == 0:
        die("Could not find the chat view's `client = ...Client(...)` line.")
    text = new_text
    changes.append("chat client -> CerebrasClient")

    # 3) Point the CHAT view's model setting at CEREBRAS_MODEL. Scope this to the part
    #    of the file BEFORE the crop-diagnosis (vision) view so we never touch the
    #    Gemini-powered vision path.
    repl = "getattr(settings, 'CEREBRAS_MODEL', '%s')" % CEREBRAS_DEFAULT_MODEL
    marker = "\nclass CropDiagnosisView"
    if marker in text:
        head, tail = text.split(marker, 1)
        tail = marker + tail
    else:
        head, tail = text, ""
    head, a = re.subn(r"getattr\(settings, '(?:OLLAMA|GEMINI)_MODEL'[^)]*\)", repl, head)
    head, b = re.subn(r"settings\.(?:OLLAMA|GEMINI)_MODEL", repl, head)
    text = head + tail
    changes.append(f"chat model refs -> CEREBRAS_MODEL ({a + b} replaced)")

    return text, changes


def patch_settings(text):
    if "CEREBRAS_API_KEY" in text and "CEREBRAS_MODEL" in text:
        return text, "CEREBRAS settings already present"
    block = (
        "\n# ==================== CEREBRAS (Dale AI) ====================\n"
        "CEREBRAS_API_KEY = env('CEREBRAS_API_KEY', default='')\n"
        "CEREBRAS_MODEL = env('CEREBRAS_MODEL', default='%s')\n" % CEREBRAS_DEFAULT_MODEL
    )
    # Insert after the OLLAMA_BASE_URL line if present, else append.
    if "OLLAMA_BASE_URL" in text:
        text = re.sub(r"(OLLAMA_BASE_URL = env\([^\n]*\)\n)", r"\1" + block, text, count=1)
    else:
        text = text.rstrip() + "\n" + block
    return text, "added CEREBRAS_API_KEY + CEREBRAS_MODEL"


def main():
    if not os.path.exists(VIEWS):
        die(f"Can't find {VIEWS}. Run this from the folder that contains manage.py.")
    if SETTINGS is None or not os.path.exists(SETTINGS):
        die("Can't find settings.py.")

    # --- cerebras_client.py ---
    if os.path.exists(CEREBRAS_CLIENT):
        print("[skip] ai/api/cerebras_client.py already exists")
    else:
        with open(CEREBRAS_CLIENT, "w", encoding="utf-8") as f:
            f.write(CEREBRAS_CLIENT_SRC)
        print("[new]  ai/api/cerebras_client.py")

    # --- views.py ---
    vtext = open(VIEWS, encoding="utf-8").read()
    new_vtext, vchanges = patch_views(vtext)
    if new_vtext != vtext:
        backup(VIEWS)
        with open(VIEWS, "w", encoding="utf-8") as f:
            f.write(new_vtext)
    print("[edit] ai/api/views.py: " + "; ".join(vchanges))

    # --- settings.py ---
    stext = open(SETTINGS, encoding="utf-8").read()
    new_stext, schange = patch_settings(stext)
    if new_stext != stext:
        backup(SETTINGS)
        with open(SETTINGS, "w", encoding="utf-8") as f:
            f.write(new_stext)
    print(f"[edit] {os.path.relpath(SETTINGS, HERE)}: {schange}")

    print(f"\nDone. Backups in {os.path.relpath(BACKUP_DIR, HERE) if os.path.exists(BACKUP_DIR) else '(none needed)'}")
    print("Add to your .env:  CEREBRAS_API_KEY=csk-...   (from cloud.cerebras.ai)")
    print("Optional:           CEREBRAS_MODEL=gpt-oss-120b  (default)")


if __name__ == "__main__":
    main()
