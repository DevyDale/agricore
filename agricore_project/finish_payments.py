#!/usr/bin/env python
"""
finish_payments.py  —  Complete Stage 1 (the parts the earlier patch didn't apply).

The previous payments patch stopped partway, so two pieces are missing:
  - the webhook ROUTE in urls.py (Flutterwave can't deliver confirmations without it)
  - the FLUTTERWAVE settings block in settings.py (so your .env keys are actually read)

This script validates EVERY change first and only writes if all checks pass — it
cannot leave things half-applied. Run from the folder with manage.py:

    python finish_payments.py
    python manage.py check
"""
import os
import sys
import shutil
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
STAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
BACKUP = os.path.join(HERE, f".finishpay_backup_{STAMP}")

URLS = SETTINGS = None
for root, _d, files in os.walk(HERE):
    if os.path.basename(root) == "agricore_project":
        if "urls.py" in files:
            URLS = os.path.join(root, "urls.py")
        if "settings.py" in files:
            SETTINGS = os.path.join(root, "settings.py")

FLW_SETTINGS_BLOCK = '''CLOUDINARY_API_SECRET = env('CLOUDINARY_API_SECRET', default='')

# ==================== FLUTTERWAVE (Payments) ====================
FLW_PUBLIC_KEY = env('FLW_PUBLIC_KEY', default='')
FLW_SECRET_KEY = env('FLW_SECRET_KEY', default='')
FLW_SECRET_HASH = env('FLW_SECRET_HASH', default='')  # same value as the Flutterwave dashboard webhook hash
DEFAULT_CURRENCY = env('DEFAULT_CURRENCY', default='UGX')
PLATFORM_FEE_PERCENT = env.float('PLATFORM_FEE_PERCENT', default=2.5)
PAYMENT_REDIRECT_URL = env('PAYMENT_REDIRECT_URL', default='https://agricore-frontend.vercel.app/payment/callback')'''

# Each job: (path, [(old, new, done_marker), ...])
JOBS = [
    (URLS, [
        (
            "from escrow.api.views import EscrowViewSet",
            "from escrow.api.views import EscrowViewSet, FlutterwaveWebhookView",
            "FlutterwaveWebhookView",
        ),
        (
            "    path('api/', include(router.urls)),",
            "    path('api/', include(router.urls)),\n"
            "    path('api/payments/flutterwave/webhook/', FlutterwaveWebhookView.as_view(), name='flw_webhook'),",
            "api/payments/flutterwave/webhook/",
        ),
    ]),
    (SETTINGS, [
        (
            "CLOUDINARY_API_SECRET = env('CLOUDINARY_API_SECRET', default='')",
            FLW_SETTINGS_BLOCK,
            "FLW_SECRET_KEY",
        ),
    ]),
]


def main():
    if not URLS or not SETTINGS:
        print("[ABORT] Couldn't find urls.py / settings.py. Run from the folder with manage.py.")
        sys.exit(1)

    planned = {}   # path -> new_text
    problems = []

    for path, repls in JOBS:
        if not os.path.exists(path):
            problems.append(f"missing file: {path}")
            continue
        text = open(path, encoding="utf-8").read()
        for old, new, marker in repls:
            if marker in text:
                continue  # already applied — leave as-is
            c = text.count(old)
            if c != 1:
                problems.append(
                    f"{os.path.relpath(path, HERE)}: anchor not found exactly once "
                    f"(found {c}):\n      {old[:90]}"
                )
                continue
            text = text.replace(old, new)
        planned[path] = text

    if problems:
        print("[ABORT] Nothing written. Issues found:")
        for p in problems:
            print("  - " + p)
        sys.exit(1)

    # All good — now write everything.
    os.makedirs(BACKUP, exist_ok=True)
    for path, new_text in planned.items():
        original = open(path, encoding="utf-8").read()
        if new_text == original:
            print(f"[ok]   {os.path.relpath(path, HERE)} already complete")
            continue
        shutil.copy2(path, os.path.join(BACKUP, os.path.relpath(path, HERE).replace(os.sep, "__")))
        open(path, "w", encoding="utf-8").write(new_text)
        print(f"[edit] {os.path.relpath(path, HERE)}")

    print(f"\nDone. Backups in {os.path.relpath(BACKUP, HERE)}/")
    print("Now run: python manage.py check")


if __name__ == "__main__":
    main()
