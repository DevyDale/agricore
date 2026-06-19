"""Payment provider adapter for Agricore.  (adapter-revision: 2 - complete drop-in)

The platform migrated off Flutterwave (which now only onboards >$5M merchants in
this market) to **IntaSend**, which supports both collections and disbursements
for Uganda (UGX, MTN + Airtel mobile money) through one API.

This module is the single point of contact with the gateway. ``utils.flutterwave``
re-exports every name from here, so the escrow views, serializer and webhook keep
calling the same functions with the same signatures and the same return shapes.

Drop-in surface (what escrow/api/views.py + serializers.py call):
  new_tx_ref(prefix)                  -> str
  service_fee(amount)                 -> Decimal
  create_payment_link(amount, currency, tx_ref, customer_email,
                      customer_name, customer_phone, payment_options, meta)
                                      -> str  (hosted checkout URL)
  verify_transaction(invoice_id)      -> {"status":"success","data":{status,amount,currency,...}}
  initiate_transfer(amount, currency, account_bank, account_number,
                    beneficiary_name, reference, narration, meta)
                                      -> {"status":"success","data":{id,status,...}}
  verify_transfer(tracking_id)        -> {"status":"success","data":{status,...}}  (status UPPER)
  list_banks(country)                 -> [{"code","name"}]
  FlutterwaveError                    -> alias of PaymentError

Settings (loaded from .env via Django settings):
  INTASEND_SECRET_KEY        Bearer token (ISSecretKey_...)  -> Send Money + status
  INTASEND_PUBLISHABLE_KEY   X-IntaSend-Public-API-Key       -> Checkout
  INTASEND_TEST              True -> sandbox host, False -> live host
  PAYMENT_REDIRECT_URL       where the buyer returns after paying (optional)
"""
import os
import re
import uuid
from decimal import Decimal, ROUND_HALF_UP

import requests

try:  # works inside Django; degrades gracefully in a bare sandbox/test
    from django.conf import settings as _dj_settings
except Exception:  # pragma: no cover
    _dj_settings = None

SANDBOX_BASE = "https://sandbox.intasend.com"
LIVE_BASE = "https://payment.intasend.com"

# IntaSend rail for Uganda + Tanzania mobile money (the "XB" cross-border rail).
UG_MOMO_PROVIDER = "INTASEND-XB"

_SAFE_TEXT = re.compile(r"[^A-Za-z0-9\-_: ]+")   # name / narrative charset
_SAFE_PHONE = re.compile(r"[^0-9\-_+ ]+")        # checkout phone charset


class PaymentError(Exception):
    """Raised for any gateway-side failure (network, non-2xx, error body)."""


# Existing code catches ``flutterwave.FlutterwaveError`` -- keep it working.
FlutterwaveError = PaymentError


def _cfg(name, default=None):
    if _dj_settings is not None:
        return getattr(_dj_settings, name, default)
    return os.environ.get(name, default)


def _base():
    test = _cfg("INTASEND_TEST", True)
    if isinstance(test, str):
        test = test.strip().lower() not in ("0", "false", "no", "")
    return SANDBOX_BASE if test else LIVE_BASE


def _bearer():
    return {
        "Authorization": f"Bearer {_cfg('INTASEND_SECRET_KEY', '') or ''}",
        "Content-Type": "application/json",
    }


def _pub_headers():
    return {
        "X-IntaSend-Public-API-Key": _cfg("INTASEND_PUBLISHABLE_KEY", "") or "",
        "Content-Type": "application/json",
    }


def _safe(text, fallback=""):
    cleaned = _SAFE_TEXT.sub(" ", str(text or "")).strip()
    cleaned = re.sub(r"\s+", " ", cleaned)
    return (cleaned or fallback)[:240]


def _safe_phone(value):
    return _SAFE_PHONE.sub("", str(value or "")).strip()


def _digits(value):
    """IntaSend Send Money ``account`` must be digits only (no '+', spaces, dashes)."""
    return re.sub(r"\D", "", str(value or ""))


def _handle(resp):
    try:
        data = resp.json()
    except ValueError:
        raise PaymentError(f"Non-JSON response ({resp.status_code}): {resp.text[:200]}")
    if resp.status_code >= 400:
        detail = None
        if isinstance(data, dict):
            errs = data.get("errors")
            if errs:
                first = errs[0] if isinstance(errs, list) and errs else errs
                detail = (first or {}).get("detail") if isinstance(first, dict) else str(first)
            detail = detail or data.get("detail") or data.get("message")
        raise PaymentError(detail or f"HTTP {resp.status_code}: {resp.text[:200]}")
    return data


def new_tx_ref(prefix="agc"):
    """A unique, idempotent reference for one payment attempt."""
    return f"{prefix}-{uuid.uuid4().hex[:18]}"


def service_fee(amount):
    """Platform service fee as a Decimal, from settings.PLATFORM_FEE_PERCENT."""
    pct = Decimal(str(_cfg("PLATFORM_FEE_PERCENT", 2.5)))
    return (Decimal(str(amount)) * pct / Decimal("100")).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )


def create_payment_link(amount, currency, tx_ref, customer_email,
                        customer_name="", customer_phone="",
                        payment_options="mobilemoneyuganda,card", meta=None):
    """Create an IntaSend hosted Checkout link and return the URL (string).

    Same signature/return as the old Flutterwave function, so the escrow ``pay``
    action is unchanged. The hosted page offers MTN/Airtel mobile money + card.
    ``payment_options`` is accepted for compatibility but IntaSend picks methods
    from the currency/country automatically.
    """
    first, _, last = (customer_name or "Agricore Buyer").partition(" ")
    body = {
        "amount": str(amount),
        "currency": currency or "UGX",
        "email": customer_email or "buyer@agricore.app",
        "first_name": _safe(first, "Agricore")[:45],
        "last_name": _safe(last or "Buyer", "Buyer")[:45],
        "api_ref": str(tx_ref)[:140],
    }
    redirect = _cfg("PAYMENT_REDIRECT_URL", "") or ""
    if redirect:
        body["redirect_url"] = redirect
    phone = _safe_phone(customer_phone)
    if phone:
        body["phone_number"] = phone[:30]
    try:
        resp = requests.post(
            f"{_base()}/api/v1/checkout/", json=body, headers=_pub_headers(), timeout=30
        )
    except requests.RequestException as e:
        raise PaymentError(str(e))
    data = _handle(resp)
    link = data.get("url")
    if not link:
        raise PaymentError("No checkout URL returned")
    return link


def verify_transaction(invoice_id):
    """Server-side verify a collection by its IntaSend invoice id.

    Normalized to the shape the webhook reads::
        {"status":"success","data":{"status": "successful"|"failed"|"pending",
                                    "amount": <value>, "currency": <ccy>, "id": ...}}
    """
    try:
        resp = requests.post(
            f"{_base()}/api/v1/payment/status/",
            json={"invoice_id": invoice_id}, headers=_bearer(), timeout=30,
        )
    except requests.RequestException as e:
        raise PaymentError(str(e))
    data = _handle(resp)
    inv = data.get("invoice") or {}
    state = (inv.get("state") or "").upper()
    if state == "COMPLETE":
        norm = "successful"
    elif state in ("FAILED", "CANCELED"):
        norm = "failed"
    else:
        norm = "pending"
    return {
        "status": "success",
        "data": {
            "id": inv.get("invoice_id") or invoice_id,
            "status": norm,
            "amount": inv.get("value"),
            "currency": inv.get("currency"),
            "raw": data,
        },
    }


def initiate_transfer(amount, currency, account_bank, account_number,
                      beneficiary_name, reference, narration="Agricore payout", meta=None):
    """Send a payout (Send Money) to a seller/rider. Returns the Flutterwave-shaped
    dict the escrow code reads: ``{"status":"success","data":{"id","status"}}``."""
    txn = {
        "name": _safe(beneficiary_name, "Agricore payee"),
        "account": _digits(account_number),
        "amount": str(amount),
        "narrative": _safe(narration, "Agricore payout"),
    }
    is_bank = bool(account_bank) and str(account_bank).upper() not in ("MPS", "MOMO", "")
    if is_bank:
        txn["bank_code"] = str(account_bank)
        provider = "PESALINK"
    else:
        provider = UG_MOMO_PROVIDER
    payload = {
        "currency": currency or "UGX",
        "provider": provider,
        "country": "UG",
        "requires_approval": "NO",
        "transactions": [txn],
    }
    if reference:
        payload["batch_reference"] = str(reference)[:70]
    try:
        resp = requests.post(
            f"{_base()}/api/v1/send-money/initiate/",
            json=payload, headers=_bearer(), timeout=30,
        )
    except requests.RequestException as e:
        raise PaymentError(str(e))
    data = _handle(resp)
    txs = data.get("transactions") or []
    tx0 = txs[0] if txs else {}
    return {
        "status": "success",
        "data": {
            "id": data.get("tracking_id") or tx0.get("request_reference_id") or "",
            "status": data.get("status") or tx0.get("status") or "",
            "tracking_id": data.get("tracking_id"),
            "raw": data,
        },
    }


def verify_transfer(tracking_id):
    """Check a payout's status by its IntaSend tracking id. Normalized so the
    webhook's ``(...).get('status').upper()`` yields SUCCESSFUL / FAILED / PENDING."""
    try:
        resp = requests.post(
            f"{_base()}/api/v1/send-money/status/",
            json={"tracking_id": tracking_id}, headers=_bearer(), timeout=30,
        )
    except requests.RequestException as e:
        raise PaymentError(str(e))
    data = _handle(resp)
    txs = data.get("transactions") or []
    tx0 = txs[0] if txs else {}
    blob = " ".join(str(x) for x in [data.get("status"), tx0.get("status"),
                                      data.get("status_code"), tx0.get("status_code")]).lower()
    if any(k in blob for k in ("complete", "success", "sent", "paid")):
        norm = "SUCCESSFUL"
    elif any(k in blob for k in ("fail", "reject", "cancel", "error")):
        norm = "FAILED"
    else:
        norm = "PENDING"
    return {
        "status": "success",
        "data": {"id": tracking_id, "status": norm, "raw": data},
    }


def list_banks(country="UG"):
    """Banks available for payouts as ``[{"code","name"}, ...]``.

    IntaSend payouts in Uganda are mobile money; bank payout there is not yet
    wired, so for UG this returns ``[]`` and the bank picker falls back to a plain
    field (sellers/riders are paid by MoMo). KE returns IntaSend's bank codes.
    """
    country = (country or "UG").upper()
    if country != "KE":
        return []
    try:
        resp = requests.get(
            f"{_base()}/api/v1/send-money/bank-codes/",
            headers=_bearer(), timeout=30,
        )
    except requests.RequestException as e:
        raise PaymentError(str(e))
    data = _handle(resp)
    rows = data if isinstance(data, list) else (data.get("results") or data.get("bank_codes") or [])
    banks = [
        {"code": str(b.get("code") or b.get("bank_code") or ""),
         "name": b.get("name") or b.get("bank_name") or ""}
        for b in rows if (b.get("code") or b.get("bank_code"))
    ]
    banks.sort(key=lambda b: b["name"])
    return banks


def verify_payment(invoice_id):
    """Alias kept for forward code that imported it; same as verify_transaction."""
    return verify_transaction(invoice_id)
