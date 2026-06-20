#!/usr/bin/env python
"""
fix_tasks.py  —  Make ai/tasks.py import-safe and Cerebras-powered.

Run from the folder that contains manage.py:

    python fix_tasks.py

Why: ai/tasks.py currently crashes the moment Celery imports it, because of
  - `from groq import Groq`            (groq isn't installed / not used anymore)
  - `from crops.models import CropExpense`  (that model is commented out)
  - a module-level `client = Groq(settings.GROQ_API_KEY)`  (key no longer exists)
That one bad import takes down the whole Celery worker.

This rewrites the file so that:
  - top-level imports are tiny and always safe (celery, settings, json, logging),
  - the daily-prediction task runs on Cerebras (the provider Dale now uses),
  - the receipt parser keeps working (extract + AI parse + log) but no longer
    writes to the deleted CropExpense model; heavy/optional deps (PyPDF2, magic)
    are imported lazily so they can never break worker startup.

Backs up the original first; nothing else is touched.
"""
import os
import sys
import shutil
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
TASKS = os.path.join(HERE, "ai", "tasks.py")

if not os.path.exists(TASKS):
    print(f"[ABORT] Can't find {TASKS}. Run this from the folder that contains manage.py.")
    sys.exit(1)

STAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
BACKUP = os.path.join(HERE, f".tasks_backup_{STAMP}")
os.makedirs(BACKUP, exist_ok=True)
shutil.copy2(TASKS, os.path.join(BACKUP, "ai__tasks.py"))

NEW = '''"""Celery tasks for the AI module.

Kept deliberately import-safe: only lightweight, always-available modules are
imported at the top so that a Celery worker can load this file without crashing.
Everything heavy or optional is imported lazily inside the task that needs it.
"""
from celery import shared_task
from django.conf import settings
import json
import logging

logger = logging.getLogger(__name__)


def _llm():
    """Build the Cerebras chat client (same one Dale's chat uses)."""
    from ai.api.cerebras_client import CerebrasClient
    return CerebrasClient(
        getattr(settings, "CEREBRAS_API_KEY", ""),
        getattr(settings, "CEREBRAS_MODEL", "gpt-oss-120b"),
    )


def _content(completion):
    """Pull the text out of an OpenAI-style completion, safely."""
    try:
        return completion["choices"][0]["message"]["content"] or ""
    except (KeyError, IndexError, TypeError):
        return ""


@shared_task
def generate_daily_predictions():
    """Generate a simple AI yield outlook per farm. Scaffold: inputs are still
    placeholders; swap in real EnvironmentalData when ready."""
    from farms.models import Farm
    from .models import Prediction

    client = _llm()
    created = 0
    for farm in Farm.objects.all():
        inputs = {"temperature": 25, "rainfall": 10}  # TODO: pull latest EnvironmentalData
        prompt = (
            f"Predict the yield outlook for farm {farm.id} given {inputs}. "
            'Respond ONLY with JSON like {"value": <number>, "unit": "<string>", "summary": "<short string>"}.'
        )
        reply = _content(client.chat(
            messages=[{"role": "user", "content": prompt}],
            temperature=0.2,
            max_tokens=300,
        ))

        # If the provider errored, the client returns a friendly "(Dale tripped...)"
        # string. Don't store a junk prediction for that farm.
        if not reply or reply.startswith("(Dale tripped on a wire"):
            logger.warning("Skipping prediction for farm %s: %s", farm.id, reply[:120])
            continue

        try:
            result = json.loads(reply)
        except (json.JSONDecodeError, TypeError):
            result = {"value": 0, "summary": reply[:500]}

        Prediction.objects.create(
            farm=farm,
            prediction_type="yield",
            inputs=inputs,
            result=result,
            confidence=0.9,
            explanation="AI-generated yield outlook (Cerebras)",
        )
        created += 1

    return f"Created {created} prediction(s)"


@shared_task
def analyze_receipt(attachment_id):
    """Download a receipt PDF, extract its text, and ask the AI to pull out the
    expense details. Returns the AI's JSON string and logs it.

    NOTE: this intentionally does NOT auto-create an Expense. The expenses.Expense
    model requires farm + category context that a bare Attachment doesn't carry;
    wire creation in once the upload flow provides those.
    """
    import requests
    from io import BytesIO
    from accounts.models import Attachment
    from .models import AILog

    try:
        attachment = Attachment.objects.get(id=attachment_id)
    except Attachment.DoesNotExist:
        logger.error("Attachment %s not found", attachment_id)
        return f"Attachment {attachment_id} not found"

    try:
        resp = requests.get(attachment.url, timeout=10)
        resp.raise_for_status()
    except requests.RequestException as e:
        logger.error("Failed to download attachment %s: %s", attachment_id, e)
        return f"Failed to download attachment: {e}"

    # Optional parsing deps imported lazily so they can never break worker startup.
    try:
        from PyPDF2 import PdfReader
        import magic
    except ImportError as e:
        logger.error("Receipt parsing dependency missing: %s", e)
        return f"Receipt parsing dependency missing: {e}"

    buf = BytesIO(resp.content)
    mime = magic.from_buffer(buf.getvalue(), mime=True)
    if mime != "application/pdf":
        logger.error("Attachment %s is not a PDF: %s", attachment_id, mime)
        return f"Invalid PDF: {mime}"

    try:
        reader = PdfReader(buf)
        text = "".join((page.extract_text() or "") for page in reader.pages)
    except Exception as e:
        logger.error("PDF extraction failed for %s: %s", attachment_id, e)
        return f"PDF extraction failed: {e}"

    prompt = (
        f"Extract expense details from this receipt: {text}. "
        "Output JSON with amount, category, date, vendor."
    )
    result = _content(_llm().chat(
        messages=[{"role": "user", "content": prompt}],
        temperature=0.1,
        max_tokens=400,
    ))

    try:
        AILog.objects.create(
            user=attachment.uploaded_by,
            context_type="receipt",
            context_id=attachment.id,
            prompt=prompt,
            response=result,
            model=getattr(settings, "CEREBRAS_MODEL", "gpt-oss-120b"),
        )
    except Exception as e:
        logger.error("Failed to log receipt analysis for %s: %s", attachment_id, e)

    return result
'''

with open(TASKS, "w", encoding="utf-8") as f:
    f.write(NEW)

print("[rewrote] ai/tasks.py  (import-safe; daily predictions now run on Cerebras)")
print(f"Backup of the original: {os.path.relpath(BACKUP, HERE)}/ai__tasks.py")
print("\nNothing else changed. Run `python manage.py check` to confirm.")
