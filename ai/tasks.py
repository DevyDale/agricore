from celery import shared_task
from groq import Groq  # Use Groq instead of OpenAI
from django.conf import settings
from PyPDF2 import PdfReader
import magic
import requests
from io import BytesIO
from accounts.models import Attachment
from crops.models import CropExpense
from .models import AILog, Prediction
from farms.models import Farm
import json
import logging

logger = logging.getLogger(__name__)
client = Groq(api_key=settings.GROQ_API_KEY)  # Initialize Groq client

@shared_task
def analyze_receipt(attachment_id):
    try:
        attachment = Attachment.objects.get(id=attachment_id)
    except Attachment.DoesNotExist:
        logger.error(f"Attachment {attachment_id} not found")
        return f"Attachment {attachment_id} not found"

    try:
        response = requests.get(attachment.url, timeout=10)
        response.raise_for_status()
    except requests.RequestException as e:
        logger.error(f"Failed to download attachment {attachment_id}: {str(e)}")
        return f"Failed to download attachment: {str(e)}"

    file_content = BytesIO(response.content)
    mime = magic.from_buffer(file_content.getvalue(), mime=True)
    if mime != 'application/pdf':
        logger.error(f"Attachment {attachment_id} is not a PDF: {mime}")
        return f"Invalid PDF: {mime}"

    try:
        reader = PdfReader(file_content)
        text = ''
        for page in reader.pages:
            extracted = page.extract_text() or ''
            text += extracted
    except Exception as e:
        logger.error(f"Failed to extract text from PDF {attachment_id}: {str(e)}")
        return f"PDF extraction failed: {str(e)}"

    prompt = f"Extract expense details from this receipt: {text}. Output JSON with amount, category, date, vendor."
    try:
        response = client.chat.completions.create(
            model="llama3-8b-8192",  # Groq's free Llama 3 model
            messages=[{"role": "user", "content": prompt}]
        )
        result = response.choices[0].message.content
    except Exception as e:
        logger.error(f"Groq API call failed for attachment {attachment_id}: {str(e)}")
        return f"Groq API error: {str(e)}"

    try:
        data = json.loads(result)
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON response for attachment {attachment_id}: {result}")
        return f"Invalid JSON response: {str(e)}"

    expense = CropExpense.objects.create(
        crop_id=attachment.owner_id if attachment.owner_type == 'expense' else None,
        amount=data.get('amount', 0),
        currency='USD',
        category=data.get('category', ''),
        incurred_on=data.get('date', None),
        additional_notes=data.get('vendor', '')
    )
    AILog.objects.create(
        user=attachment.uploaded_by,
        context_type='receipt',
        context_id=attachment.id,
        prompt=prompt,
        response=result,
        model='llama3-8b-8192'  # Log Groq model
    )
    return result

@shared_task
def generate_daily_predictions():
    for farm in Farm.objects.all():
        # Dummy inputs; replace with real data (e.g., from env data, crops)
        inputs = {'temperature': 25, 'rainfall': 10}  # Example
        prompt = f"Predict yield for farm {farm.id} based on {inputs}."
        try:
            response = client.chat.completions.create(
                model="llama3-8b-8192",  # Groq's free Llama 3 model
                messages=[{"role": "user", "content": prompt}]
            )
            result_str = response.choices[0].message.content
        except Exception as e:
            logger.error(f"Groq API call failed for farm {farm.id}: {str(e)}")
            continue  # Skip to next farm

        try:
            result = json.loads(result_str)
        except json.JSONDecodeError:
            logger.error(f"Invalid JSON response for farm {farm.id}: {result_str}")
            result = {'value': 0}

        Prediction.objects.create(
            farm=farm,
            prediction_type='yield',
            inputs=inputs,
            result=result,
            confidence=0.9,
            explanation='AI generated based on weather data'
        )