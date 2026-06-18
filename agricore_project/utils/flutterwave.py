"""Flutterwave (v3) client for Agricore payments.

Collections use Flutterwave **Standard** (hosted checkout), so card details never
touch our server and the hosted page offers MTN/Airtel mobile money and cards.
"""
import uuid
import requests
from decimal import Decimal, ROUND_HALF_UP
from django.conf import settings

FLW_BASE = "https://api.flutterwave.com/v3"


class FlutterwaveError(Exception):
    pass


def _headers():
    return {
        "Authorization": f"Bearer {getattr(settings, 'FLW_SECRET_KEY', '')}",
        "Content-Type": "application/json",
    }


def new_tx_ref(prefix="agc"):
    """A unique, idempotent reference for one payment attempt."""
    return f"{prefix}-{uuid.uuid4().hex[:18]}"


def service_fee(amount):
    """Platform service fee as a Decimal, from settings.PLATFORM_FEE_PERCENT."""
    pct = Decimal(str(getattr(settings, "PLATFORM_FEE_PERCENT", 2.5)))
    return (Decimal(str(amount)) * pct / Decimal("100")).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )


def _handle(resp):
    try:
        data = resp.json()
    except ValueError:
        raise FlutterwaveError(f"Non-JSON response ({resp.status_code}): {resp.text[:200]}")
    if resp.status_code >= 400 or data.get("status") != "success":
        raise FlutterwaveError(data.get("message") or f"HTTP {resp.status_code}")
    return data


def create_payment_link(amount, currency, tx_ref, customer_email,
                        customer_name="", customer_phone="",
                        payment_options="mobilemoneyuganda,card", meta=None):
    """Create a Flutterwave Standard checkout link. Returns the hosted URL."""
    payload = {
        "tx_ref": tx_ref,
        "amount": amount,
        "currency": currency,
        "redirect_url": getattr(settings, "PAYMENT_REDIRECT_URL", ""),
        "payment_options": payment_options,
        "customer": {
            "email": customer_email or "buyer@agricore.app",
            "name": customer_name or "",
            "phonenumber": customer_phone or "",
        },
        "customizations": {"title": "Agricore", "description": "Marketplace escrow payment"},
        "meta": meta or {},
    }
    try:
        resp = requests.post(f"{FLW_BASE}/payments", json=payload, headers=_headers(), timeout=30)
    except requests.RequestException as e:
        raise FlutterwaveError(str(e))
    data = _handle(resp)
    link = (data.get("data") or {}).get("link")
    if not link:
        raise FlutterwaveError("No checkout link returned")
    return link


def verify_transaction(flw_tx_id):
    """Server-side verify a transaction by its Flutterwave id."""
    try:
        resp = requests.get(
            f"{FLW_BASE}/transactions/{flw_tx_id}/verify", headers=_headers(), timeout=30
        )
    except requests.RequestException as e:
        raise FlutterwaveError(str(e))
    return _handle(resp)


def initiate_transfer(amount, currency, account_bank, account_number,
                      beneficiary_name, reference, narration="Agricore payout", meta=None):
    """Send a payout (Transfer). For mobile money use account_bank="MPS" and
    account_number = the recipient's phone in international format."""
    payload = {
        "account_bank": account_bank,
        "account_number": account_number,
        "amount": amount,
        "currency": currency,
        "beneficiary_name": beneficiary_name,
        "reference": reference,
        "narration": narration,
    }
    if meta:
        payload["meta"] = meta
    try:
        resp = requests.post(f"{FLW_BASE}/transfers", json=payload, headers=_headers(), timeout=30)
    except requests.RequestException as e:
        raise FlutterwaveError(str(e))
    return _handle(resp)


def verify_transfer(transfer_id):
    """Check a payout's status by its Flutterwave transfer id."""
    try:
        resp = requests.get(f"{FLW_BASE}/transfers/{transfer_id}", headers=_headers(), timeout=30)
    except requests.RequestException as e:
        raise FlutterwaveError(str(e))
    return _handle(resp)


_BANKS_CACHE = {}


def list_banks(country="UG"):
    """Flutterwave's supported banks for a country as
    [{"code": str, "name": str}, ...], sorted by name. Cached per process
    (the list rarely changes). Raises FlutterwaveError on a gateway failure."""
    country = (country or "UG").upper()
    cached = _BANKS_CACHE.get(country)
    if cached is not None:
        return cached
    try:
        resp = requests.get(f"{FLW_BASE}/banks/{country}", headers=_headers(), timeout=30)
    except requests.RequestException as e:
        raise FlutterwaveError(str(e))
    data = _handle(resp)
    banks = [
        {"code": str(b.get("code") or ""), "name": b.get("name") or ""}
        for b in (data.get("data") or [])
        if b.get("code")
    ]
    banks.sort(key=lambda b: b["name"])
    if banks:
        _BANKS_CACHE[country] = banks
    return banks
