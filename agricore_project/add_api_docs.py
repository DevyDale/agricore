#!/usr/bin/env python3
"""
add_api_docs.py  (idempotent, all-or-nothing)

Adds interactive API documentation via drf-spectacular:

  requirements.txt   + drf-spectacular
  settings.py        + 'drf_spectacular' in INSTALLED_APPS
                     + REST_FRAMEWORK['DEFAULT_SCHEMA_CLASS']
                     + SPECTACULAR_SETTINGS (title / description / version)
  urls.py            + /api/schema/   (raw OpenAPI schema)
                     + /api/docs/     (Swagger UI - clickable, "try it out")
                     + /api/redoc/    (ReDoc - clean reference view)

Run from the folder that contains manage.py:
    python add_api_docs.py

Then:
    pip install drf-spectacular
    python manage.py spectacular --file schema.yml   # generates + validates the whole API
    python manage.py runserver                       # then open http://127.0.0.1:8000/api/docs/

Safe to run more than once. Backs up every edited file first.
"""

import os
import sys
import shutil
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
STAMP = datetime.now().strftime("%Y%m%d-%H%M%S")
BACKUP = HERE / f".api_docs_backup_{STAMP}"


def find_file(rel_parts):
    """Direct path first; fall back to a walk that SKIPS hidden dirs."""
    direct = HERE.joinpath(*rel_parts)
    if direct.is_file():
        return direct
    suffix = os.path.join(*rel_parts)
    target = rel_parts[-1]
    for root, dirs, files in os.walk(HERE):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        if target in files:
            cand = Path(root) / target
            if str(cand).endswith(suffix):
                return cand
    return None


SETTINGS = find_file(["agricore_project", "settings.py"])
URLS = find_file(["agricore_project", "urls.py"])
REQS = find_file(["requirements.txt"])

if not (SETTINGS and URLS and REQS):
    print("ERROR: could not locate target files.")
    print("  settings.py     :", SETTINGS)
    print("  urls.py         :", URLS)
    print("  requirements.txt:", REQS)
    print("Run this from the folder that contains manage.py.")
    sys.exit(1)


SETTINGS_END_BLOCK = '''

# ==================== API DOCS (drf-spectacular) ====================
REST_FRAMEWORK['DEFAULT_SCHEMA_CLASS'] = 'drf_spectacular.openapi.AutoSchema'

SPECTACULAR_SETTINGS = {
    'TITLE': 'Agricore API',
    'DESCRIPTION': (
        'Backend API for the Agricore agricultural commerce platform: '
        'farms, crops, livestock, inventory, marketplace, escrow payments, '
        'market prices, logistics, workforce, AI, and notifications.'
    ),
    'VERSION': '1.0.0',
    'SERVE_INCLUDE_SCHEMA': False,
}
'''

URLS_IMPORT = (
    "from drf_spectacular.views import "
    "SpectacularAPIView, SpectacularSwaggerView, SpectacularRedocView"
)

URLS_PATHS = [
    "    path('api/schema/', SpectacularAPIView.as_view(), name='schema'),",
    "    path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),",
    "    path('api/redoc/', SpectacularRedocView.as_view(url_name='schema'), name='redoc'),",
]


def patch_settings(text):
    changed = False
    lines = text.split("\n")

    # 1) add 'drf_spectacular' to INSTALLED_APPS (after the 'rest_framework' line)
    if "drf_spectacular" not in text:
        for i, ln in enumerate(lines):
            if ln.strip() == "'rest_framework',":
                indent = ln[: len(ln) - len(ln.lstrip())]
                lines.insert(i + 1, f"{indent}'drf_spectacular',")
                changed = True
                break
        else:
            raise RuntimeError("settings.py: \"'rest_framework',\" line not found in INSTALLED_APPS")

    text = "\n".join(lines)

    # 2) append schema class + SPECTACULAR_SETTINGS at end of file
    if "SPECTACULAR_SETTINGS" not in text:
        if not text.endswith("\n"):
            text += "\n"
        text += SETTINGS_END_BLOCK
        changed = True

    return text, ("patched" if changed else "skip (already present)")


def patch_urls(text):
    if "drf_spectacular" in text and "api/schema/" in text:
        return text, "skip (already present)"

    lines = text.split("\n")

    # 1) import line after the simplejwt views import
    if "drf_spectacular" not in text:
        for i, ln in enumerate(lines):
            if ln.startswith("from rest_framework_simplejwt.views import"):
                lines.insert(i + 1, URLS_IMPORT)
                break
        else:
            raise RuntimeError("urls.py: simplejwt views import anchor not found")

    # 2) doc paths right after 'urlpatterns = ['
    if "api/schema/" not in text:
        for i, ln in enumerate(lines):
            if ln.startswith("urlpatterns = ["):
                for offset, p in enumerate(URLS_PATHS):
                    lines.insert(i + 1 + offset, p)
                break
        else:
            raise RuntimeError("urls.py: 'urlpatterns = [' anchor not found")

    return "\n".join(lines), "patched"


def patch_reqs(text):
    # match a whole-word drf-spectacular (not drf-nested-routers etc.)
    for ln in text.split("\n"):
        if ln.strip().split("==")[0].split(">=")[0].strip() == "drf-spectacular":
            return text, "skip (already present)"
    if not text.endswith("\n"):
        text += "\n"
    text += "drf-spectacular\n"
    return text, "patched"


def main():
    targets = [
        (REQS, patch_reqs),
        (SETTINGS, patch_settings),
        (URLS, patch_urls),
    ]
    results = []
    for path, fn in targets:
        original = path.read_text()
        new_text, st = fn(original)
        results.append((path, new_text, st, new_text != original))

    if not any(changed for *_, changed in results):
        for path, _, st, _ in results:
            print(f"[skip] {path.relative_to(HERE)}  ->  {st}")
        print("\nNothing to do — API docs already configured.")
        return

    BACKUP.mkdir(exist_ok=True)
    for path, new_text, st, changed in results:
        if changed:
            shutil.copy2(path, BACKUP / path.name)
            path.write_text(new_text)
            print(f"[edit] {path.relative_to(HERE)}  ->  {st}  (backup: {BACKUP.name}/{path.name})")
        else:
            print(f"[skip] {path.relative_to(HERE)}  ->  {st}")

    print("\nDone. Next steps:")
    print("  pip install drf-spectacular")
    print("  python manage.py spectacular --file schema.yml")
    print("  python manage.py runserver")
    print("\nThen open:")
    print("  http://127.0.0.1:8000/api/docs/    (Swagger UI)")
    print("  http://127.0.0.1:8000/api/redoc/   (ReDoc)")


if __name__ == "__main__":
    main()
