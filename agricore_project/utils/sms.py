"""Lightweight SMS sender for Agricore (Uganda).

Sends the buyer's delivery code to any phone, so feature-phone buyers don't need
the app. Provider is chosen by Django settings; falls back to console logging in
dev so flows work with no gateway configured.

Production settings (add to settings.py or env):
    SMS_PROVIDER = "africastalking"      # default: "console" (logs only)
    AT_USERNAME  = "your_at_username"    # "sandbox" for testing
    AT_API_KEY   = "your_at_api_key"
    AT_SENDER_ID = "AGRICORE"            # optional approved sender ID/short code
"""
import logging

try:
    import requests
except Exception:  # requests not installed -> only the console backend works
    requests = None

logger = logging.getLogger(__name__)


class SMSError(Exception):
    pass


def _setting(name, default=""):
    try:
        from django.conf import settings
        return getattr(settings, name, default)
    except Exception:
        return default


def normalize_ug(raw):
    """Best-effort normalization of a Ugandan number to +2567XXXXXXXX."""
    s = "".join(ch for ch in str(raw or "") if ch.isdigit() or ch == "+")
    if not s:
        return ""
    if s.startswith("+"):
        return s
    if s.startswith("256"):
        return "+" + s
    if s.startswith("0"):
        return "+256" + s[1:]
    if s.startswith("7") and len(s) == 9:
        return "+256" + s
    return "+" + s


def send_sms(to, message):
    """Send one SMS. Returns True if handed off to a backend, False if skipped.
    Never raises for an unconfigured gateway -- it degrades to console logging."""
    number = normalize_ug(to)
    if not number:
        logger.warning("send_sms: missing/invalid phone; skipped")
        return False

    provider = str(_setting("SMS_PROVIDER", "console")).lower()
    if provider == "africastalking":
        try:
            return _send_africastalking(number, message)
        except SMSError as e:
            logger.error("send_sms: Africa's Talking failed: %s", e)
            logger.info("[SMS:fallback] to=%s msg=%s", number, message)
            return False

    logger.info("[SMS:console] to=%s msg=%s", number, message)
    return True


def _send_africastalking(number, message):
    username = _setting("AT_USERNAME", "sandbox")
    api_key = _setting("AT_API_KEY", "")
    sender = _setting("AT_SENDER_ID", "")
    if not api_key or requests is None:
        raise SMSError("Africa's Talking not configured (AT_API_KEY missing or requests unavailable)")

    base = "https://api.sandbox.africastalking.com" if username == "sandbox" else "https://api.africastalking.com"
    url = base + "/version1/messaging"
    data = {"username": username, "to": number, "message": message}
    if sender:
        data["from"] = sender
    headers = {"apiKey": api_key, "Accept": "application/json",
               "Content-Type": "application/x-www-form-urlencoded"}
    try:
        r = requests.post(url, data=data, headers=headers, timeout=20)
    except Exception as e:
        raise SMSError(str(e))
    if r.status_code not in (200, 201):
        raise SMSError("HTTP %s: %s" % (r.status_code, (r.text or "")[:200]))
    return True
