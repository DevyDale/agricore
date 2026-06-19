"""Compatibility shim.  (re-exports utils.payments -- IntaSend adapter)

Agricore migrated its payment gateway from Flutterwave to IntaSend. The real
implementation lives in ``utils.payments``. This module re-exports the full set
of names the rest of the codebase imports as ``utils.flutterwave`` so the escrow
views, serializer, webhook and tests keep working unchanged.

New code should import from ``utils.payments`` directly.
"""
from utils.payments import (  # noqa: F401
    PaymentError,
    PaymentError as FlutterwaveError,
    new_tx_ref,
    service_fee,
    create_payment_link,
    verify_transaction,
    initiate_transfer,
    verify_transfer,
    list_banks,
    verify_payment,
)

__all__ = [
    "PaymentError",
    "FlutterwaveError",
    "new_tx_ref",
    "service_fee",
    "create_payment_link",
    "verify_transaction",
    "initiate_transfer",
    "verify_transfer",
    "list_banks",
    "verify_payment",
]
