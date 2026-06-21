"""Pesapal API 3.0 client for Agricore.

Single point of contact with Pesapal. One env var (``PESAPAL_ENV``) switches the
whole module between sandbox and live; nothing else changes when you go live.

The flow has four calls:
  1. get_access_token()        -> bearer token (valid ~5 minutes)
  2. register_ipn(token, url)  -> notification_id (do this once per IPN URL)
  3. submit_order(...)         -> {order_tracking_id, merchant_reference, redirect_url}
  4. get_transaction_status()  -> {payment_status_description: Completed/Failed/...}

Settings (loaded from .env via Django settings):
  PESAPAL_ENV            "sandbox" (default) or "live"
  PESAPAL_CONSUMER_KEY   issued by Pesapal (sandbox or live)
  PESAPAL_CONSUMER_SECRET
  PESAPAL_IPN_ID         the notification_id from register_ipn (one-time setup)
"""
import requests
from django.conf import settings

# One switch controls everything. Flip PESAPAL_ENV in .env to go live.
BASE_URLS = {
    "sandbox": "https://cybqa.pesapal.com/pesapalv3/api",
    "live": "https://pay.pesapal.com/v3/api",
}


class PesapalError(Exception):
    """Raised for any Pesapal-side failure (network, non-2xx, or error body)."""


def _base_url():
    env = (getattr(settings, "PESAPAL_ENV", "sandbox") or "sandbox").strip().lower()
    return BASE_URLS.get(env, BASE_URLS["sandbox"])


def _handle(resp):
    """Parse a Pesapal response. Pesapal returns HTTP 200 even for logical errors,
    carrying an ``error`` object in the body, so we check both."""
    try:
        data = resp.json()
    except ValueError:
        raise PesapalError(f"Non-JSON response ({resp.status_code}): {resp.text[:200]}")
    if resp.status_code >= 400:
        raise PesapalError(f"HTTP {resp.status_code}: {resp.text[:200]}")
    err = data.get("error") if isinstance(data, dict) else None
    # Pesapal sends error: null on success, or a populated object on failure.
    if isinstance(err, dict) and (err.get("code") or err.get("message") or err.get("error_type")):
        raise PesapalError(err.get("message") or err.get("code") or str(err))
    return data


def get_access_token():
    """Step 1: Authenticate. Returns a bearer token (valid ~5 minutes)."""
    try:
        resp = requests.post(
            f"{_base_url()}/Auth/RequestToken",
            json={
                "consumer_key": getattr(settings, "PESAPAL_CONSUMER_KEY", ""),
                "consumer_secret": getattr(settings, "PESAPAL_CONSUMER_SECRET", ""),
            },
            headers={"Accept": "application/json", "Content-Type": "application/json"},
            timeout=30,
        )
    except requests.RequestException as e:
        raise PesapalError(str(e))
    data = _handle(resp)
    token = data.get("token")
    if not token:
        raise PesapalError("No token returned by Pesapal.")
    return token


def register_ipn(token, ipn_url, notification_type="GET"):
    """Step 2: Register your IPN listener URL ONCE. Returns the ipn_id."""
    try:
        resp = requests.post(
            f"{_base_url()}/URLSetup/RegisterIPN",
            json={"url": ipn_url, "ipn_notification_type": notification_type},
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
                "Authorization": f"Bearer {token}",
            },
            timeout=30,
        )
    except requests.RequestException as e:
        raise PesapalError(str(e))
    data = _handle(resp)
    ipn_id = data.get("ipn_id")
    if not ipn_id:
        raise PesapalError("No ipn_id returned by Pesapal.")
    return ipn_id


def submit_order(token, *, merchant_ref, amount, description, callback_url,
                 notification_id, billing, currency="UGX", branch="Agricore"):
    """Step 3: Create the order. Returns order_tracking_id + redirect_url."""
    payload = {
        "id": merchant_ref,              # our own unique order reference
        "currency": currency or "UGX",
        "amount": float(amount),
        "description": (description or "Agricore order")[:100],
        "callback_url": callback_url,    # where the buyer lands after paying
        "redirect_mode": "",
        "notification_id": notification_id,
        "branch": branch,
        "billing_address": billing,      # dict: email/phone/name/country_code...
    }
    try:
        resp = requests.post(
            f"{_base_url()}/Transactions/SubmitOrderRequest",
            json=payload,
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
                "Authorization": f"Bearer {token}",
            },
            timeout=30,
        )
    except requests.RequestException as e:
        raise PesapalError(str(e))
    data = _handle(resp)
    if not data.get("redirect_url") or not data.get("order_tracking_id"):
        raise PesapalError("Pesapal did not return a redirect_url / order_tracking_id.")
    return data  # order_tracking_id, merchant_reference, redirect_url


def get_transaction_status(token, order_tracking_id):
    """Step 4: Query the final status of a transaction."""
    try:
        resp = requests.get(
            f"{_base_url()}/Transactions/GetTransactionStatus",
            params={"orderTrackingId": order_tracking_id},
            headers={"Accept": "application/json", "Authorization": f"Bearer {token}"},
            timeout=30,
        )
    except requests.RequestException as e:
        raise PesapalError(str(e))
    # payment_status_description: Completed / Failed / Reversed / Invalid / Pending
    return _handle(resp)
