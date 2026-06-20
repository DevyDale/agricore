#!/usr/bin/env python3
"""
Backend fix 1/N - runtime breakers:
  * requirements.txt: split the mashed 'requestscloudinary', add google-auth
    and django-filter (both imported by the code), drop unused 'openai'.
  * accounts/middleware.py: WebSocket JWT auth read SIMPLE_JWT['SIGNING_KEY'],
    a key that isn't defined -> KeyError on every socket connect. Use SimpleJWT's
    resolved settings (defaults: SIGNING_KEY=SECRET_KEY, ALGORITHM=HS256).

Run from the directory containing manage.py:
    python backend_p0_fix.py
"""
import os
import sys
import shutil
from datetime import datetime

BACKUP = ".backend_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S")

REQUIREMENTS = """django
djangorestframework
drf-nested-routers
django-environ
django-cors-headers
django-filter
Pillow

channels
channels_redis
redis

celery
django-celery-beat

groq
PyPDF2
python-magic
requests
cloudinary
google-auth

psycopg2-binary
djangorestframework-simplejwt

gunicorn
dj-database-url
python-dotenv
whitenoise
"""

MW_OLD_IMPORT = "from jwt import decode as jwt_decode"
MW_NEW_IMPORT = (
    "from jwt import decode as jwt_decode\n"
    "from rest_framework_simplejwt.settings import api_settings"
)
MW_OLD_DECODE = (
    "                decoded_data = jwt_decode(token, settings.SIMPLE_JWT['SIGNING_KEY'], "
    "algorithms=[settings.SIMPLE_JWT['ALGORITHM']])"
)
MW_NEW_DECODE = (
    "                decoded_data = jwt_decode(token, api_settings.SIGNING_KEY, "
    "algorithms=[api_settings.ALGORITHM])"
)


def backup(path):
    dest = os.path.join(BACKUP, path)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.copy2(path, dest)


def main():
    if not os.path.exists("manage.py"):
        sys.exit("ERROR: run from the directory containing manage.py (agricore_project/).")

    mw = "accounts/middleware.py"
    for p in ["requirements.txt", mw]:
        if not os.path.exists(p):
            sys.exit(f"ERROR: missing {p}")

    with open(mw, encoding="utf-8") as f:
        mw_src = f.read()
    if MW_OLD_IMPORT not in mw_src or MW_OLD_DECODE not in mw_src:
        if "api_settings.SIGNING_KEY" in mw_src:
            sys.exit("middleware already patched - nothing to do.")
        sys.exit("ERROR: middleware doesn't match expected content; aborting (no changes made).")

    os.makedirs(BACKUP, exist_ok=True)

    # requirements.txt
    backup("requirements.txt")
    with open("requirements.txt", "w", encoding="utf-8") as f:
        f.write(REQUIREMENTS)
    print("  [OK] requirements.txt rewritten (fixed requestscloudinary, +google-auth, +django-filter, -openai)")

    # middleware
    backup(mw)
    mw_src = mw_src.replace(MW_OLD_IMPORT, MW_NEW_IMPORT, 1)
    mw_src = mw_src.replace(MW_OLD_DECODE, MW_NEW_DECODE, 1)
    with open(mw, "w", encoding="utf-8") as f:
        f.write(mw_src)
    print("  [OK] accounts/middleware.py WebSocket JWT auth fixed (uses api_settings)")

    print(f"\nDone. Backups in {BACKUP}/")


if __name__ == "__main__":
    main()
