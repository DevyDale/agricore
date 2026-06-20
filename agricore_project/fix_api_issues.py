#!/usr/bin/env python3
"""
fix_api_issues.py  (idempotent, all-or-nothing)

Fixes two issues found via the OpenAPI schema:

  1. SECURITY: accounts/api/serializers.py
     CustomUserSerializer exposed `is_verified` as a writable field, so a
     client could self-verify at registration. -> make it read-only.
     (`role` stays writable on purpose: it's a user category the user picks
      at signup -- farmer / retailer / specialized -- not a permission.)

  2. DUPLICATE ROUTE: agricore_project/urls.py
     crop-cycles was registered twice -- on the main router (/api/crop-cycles/)
     and again via crops.urls (/crops/api/crop-cycles/). -> drop the crops.urls
     include so only the canonical /api/crop-cycles/ remains.

Run from the folder that contains manage.py:
    python fix_api_issues.py
    python manage.py check

Safe to run more than once. Backs up every edited file first.
"""

import os
import sys
import shutil
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
STAMP = datetime.now().strftime("%Y%m%d-%H%M%S")
BACKUP = HERE / f".api_fixes_backup_{STAMP}"


def find_file(rel_parts):
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


SERIALIZERS = find_file(["accounts", "api", "serializers.py"])
URLS = find_file(["agricore_project", "urls.py"])

if not (SERIALIZERS and URLS):
    print("ERROR: could not locate target files.")
    print("  accounts/api/serializers.py:", SERIALIZERS)
    print("  agricore_project/urls.py    :", URLS)
    print("Run this from the folder that contains manage.py.")
    sys.exit(1)


def patch_serializers(text):
    if "'is_verified': {'read_only': True}" in text:
        return text, "skip (already read-only)"
    lines = text.split("\n")
    # anchor on CustomUserSerializer's last_login read-only line, then insert after it
    for i, ln in enumerate(lines):
        if ln.strip() == "'last_login': {'read_only': True},":
            indent = ln[: len(ln) - len(ln.lstrip())]
            lines.insert(i + 1, f"{indent}'is_verified': {{'read_only': True}},")
            return "\n".join(lines), "patched"
    raise RuntimeError(
        "serializers.py: anchor \"'last_login': {'read_only': True},\" not found"
    )


def patch_urls(text):
    lines = text.split("\n")
    out = []
    removed = False
    for ln in lines:
        if "include('crops.urls'" in ln or 'include("crops.urls"' in ln:
            removed = True
            continue  # drop this line
        out.append(ln)
    if not removed:
        return text, "skip (crops.urls include not present)"
    return "\n".join(out), "patched"


def main():
    targets = [(SERIALIZERS, patch_serializers), (URLS, patch_urls)]
    results = []
    for path, fn in targets:
        original = path.read_text()
        new_text, st = fn(original)
        results.append((path, new_text, st, new_text != original))

    if not any(changed for *_, changed in results):
        for path, _, st, _ in results:
            print(f"[skip] {path.relative_to(HERE)}  ->  {st}")
        print("\nNothing to do -- both fixes already applied.")
        return

    BACKUP.mkdir(exist_ok=True)
    for path, new_text, st, changed in results:
        if changed:
            shutil.copy2(path, BACKUP / path.name)
            path.write_text(new_text)
            print(f"[edit] {path.relative_to(HERE)}  ->  {st}  (backup: {BACKUP.name}/{path.name})")
        else:
            print(f"[skip] {path.relative_to(HERE)}  ->  {st}")

    print("\nDone. is_verified is now server-controlled; crop-cycles is single-routed.")
    print("Next:")
    print("  python manage.py check")
    print("  python manage.py runserver   (then re-open /api/docs/ to confirm)")


if __name__ == "__main__":
    main()
