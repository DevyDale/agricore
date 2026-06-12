"""Celery tasks for the AI module.

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
        try:
            from weather.services import weather_summary_for_ai
            _w = weather_summary_for_ai(farm)
            inputs = _w if _w else {"temperature": 25, "rainfall": 10}
        except Exception:
            inputs = {"temperature": 25, "rainfall": 10}
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
