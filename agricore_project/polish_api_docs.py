#!/usr/bin/env python3
"""
polish_api_docs.py  (idempotent, all-or-nothing)

Adds @extend_schema annotations so the OpenAPI docs read accurately for the
core custom endpoints (no more misleading request bodies / "no response body"):

  escrow/api/views.py      pay / fund / release   -> request=None + real responses
  notifications/api/views  unread_count / read / read_all
  ai/api/views.py          DaleAIChatView / CropDiagnosisView (request + response)
  accounts/api/views.py    GoogleAuthView / CurrentUserView (request + response)

Run from the folder that contains manage.py:
    python polish_api_docs.py
    python manage.py spectacular --file schema.yml   # re-validate
    python manage.py runserver                       # re-open /api/docs/

Safe to run more than once. Backs up every edited file first.
"""

import os
import sys
import shutil
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
STAMP = datetime.now().strftime("%Y%m%d-%H%M%S")
BACKUP = HERE / f".docs_polish_backup_{STAMP}"

IMPORTS = [
    "from drf_spectacular.utils import extend_schema, inline_serializer, OpenApiResponse",
    "from rest_framework import serializers",
]

# Per file: list of (class_name, def_signature, decorator_line)
PLAN = {
    ("escrow", "api", "views.py"): [
        ("EscrowViewSet", "def pay(",
         '    @extend_schema(request=None, responses=inline_serializer(name="EscrowPayResponse", fields={"checkout_link": serializers.URLField(), "tx_ref": serializers.CharField(), "amount": serializers.CharField(), "service_fee": serializers.CharField(), "currency": serializers.CharField()}))'),
        ("EscrowViewSet", "def fund(",
         '    @extend_schema(request=None, responses=EscrowSerializer)'),
        ("EscrowViewSet", "def release(",
         '    @extend_schema(request=None, responses=OpenApiResponse(description="Payout to the seller is initiated; the escrow flips to \'released\' once Flutterwave confirms the payout via webhook."))'),
    ],
    ("notifications", "api", "views.py"): [
        ("NotificationViewSet", "def unread_count(",
         '    @extend_schema(responses=inline_serializer(name="UnreadCountResponse", fields={"unread": serializers.IntegerField()}))'),
        ("NotificationViewSet", "def read(",
         '    @extend_schema(request=None, responses=NotificationSerializer)'),
        ("NotificationViewSet", "def read_all(",
         '    @extend_schema(request=None, responses=inline_serializer(name="ReadAllResponse", fields={"marked_read": serializers.IntegerField()}))'),
    ],
    ("ai", "api", "views.py"): [
        ("DaleAIChatView", "def post(",
         '    @extend_schema(request=inline_serializer(name="DaleAskRequest", fields={"prompt": serializers.CharField(), "context": serializers.JSONField(required=False), "history": serializers.JSONField(required=False)}), responses=inline_serializer(name="DaleAskResponse", fields={"reply": serializers.CharField(), "log_id": serializers.IntegerField(), "action": serializers.JSONField()}))'),
        ("CropDiagnosisView", "def post(",
         '    @extend_schema(request={"multipart/form-data": inline_serializer(name="CropDiagnoseRequest", fields={"image": serializers.ImageField(), "prompt": serializers.CharField(required=False), "crop": serializers.CharField(required=False)})}, responses=OpenApiResponse(description="Structured crop diagnosis (JSON)."))'),
    ],
    ("accounts", "api", "views.py"): [
        ("GoogleAuthView", "def post(",
         '    @extend_schema(request=inline_serializer(name="GoogleAuthRequest", fields={"token": serializers.CharField()}), responses=inline_serializer(name="GoogleAuthResponse", fields={"access": serializers.CharField(), "refresh": serializers.CharField(), "created": serializers.BooleanField(), "user": CustomUserSerializer()}))'),
        ("CurrentUserView", "def get(",
         '    @extend_schema(responses=CustomUserSerializer)'),
    ],
}


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


def ensure_imports(lines):
    text = "\n".join(lines)
    changed = False
    # find anchor: first line starting with "from rest_framework"
    anchor = None
    for i, ln in enumerate(lines):
        if ln.startswith("from rest_framework"):
            anchor = i
            break
    if anchor is None:
        anchor = 0
    to_add = []
    if "drf_spectacular.utils" not in text:
        to_add.append(IMPORTS[0])
    # only add the rest_framework serializers import if not already imported exactly
    if not any(l.strip() == "from rest_framework import serializers" for l in lines):
        to_add.append(IMPORTS[1])
    if to_add:
        for off, imp in enumerate(to_add):
            lines.insert(anchor + 1 + off, imp)
        changed = True
    return lines, changed


def insert_decorator(lines, class_name, def_sig, decorator):
    # locate class
    start = None
    for i, ln in enumerate(lines):
        if ln.startswith(f"class {class_name}"):
            start = i
            break
    if start is None:
        raise RuntimeError(f"class {class_name} not found")
    # locate def after class
    def_idx = None
    for i in range(start, len(lines)):
        if def_sig in lines[i] and lines[i].lstrip().startswith("def "):
            def_idx = i
            break
    if def_idx is None:
        raise RuntimeError(f"'{def_sig}' not found after class {class_name}")
    # find the top of the contiguous decorator block directly above this def
    ins = def_idx
    while ins - 1 >= 0 and lines[ins - 1].lstrip().startswith("@"):
        ins -= 1
    # idempotency: only skip if THIS method's decorator block already has one
    for j in range(ins, def_idx):
        if "extend_schema" in lines[j]:
            return lines, False
    lines.insert(ins, decorator)
    return lines, True


def patch_file(path, actions):
    lines = path.read_text().split("\n")
    lines, imports_changed = ensure_imports(lines)
    any_action = False
    for class_name, def_sig, decorator in actions:
        lines, ch = insert_decorator(lines, class_name, def_sig, decorator)
        any_action = any_action or ch
    new_text = "\n".join(lines)
    return new_text, (imports_changed or any_action)


def main():
    results = []
    for rel, actions in PLAN.items():
        path = find_file(list(rel))
        if not path:
            print("ERROR: could not find", os.path.join(*rel))
            print("Run this from the folder that contains manage.py.")
            sys.exit(1)
        original = path.read_text()
        new_text, changed = patch_file(path, actions)
        results.append((path, original, new_text, changed))

    if not any(c for *_, c in results):
        for path, *_ in results:
            print(f"[skip] {path.relative_to(HERE)}  ->  already annotated")
        print("\nNothing to do -- docs already polished.")
        return

    BACKUP.mkdir(exist_ok=True)
    for path, original, new_text, changed in results:
        if changed:
            shutil.copy2(path, BACKUP / f"{path.parent.parent.name}_{path.name}")
            path.write_text(new_text)
            print(f"[edit] {path.relative_to(HERE)}")
        else:
            print(f"[skip] {path.relative_to(HERE)}  (already annotated)")

    print("\nDone. Re-validate and view:")
    print("  python manage.py spectacular --file schema.yml")
    print("  python manage.py runserver   (then re-open /api/docs/)")


if __name__ == "__main__":
    main()
