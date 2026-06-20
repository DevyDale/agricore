#!/usr/bin/env python3
"""
harden_google_auth.py  (idempotent, all-or-nothing)

Hardens the EXISTING Google sign-in endpoint (POST /api/auth/google/):

  settings.py        + GOOGLE_OAUTH_CLIENT_IDS (env.list, supports many client IDs)
  accounts/api/views + GoogleAuthView rewritten to:
                         - read the client IDs from settings (no hardcoded ID)
                         - accept multiple audiences (Android / iOS / web)
                         - require Google's email_verified == True
                         - mark the user is_verified = True
                         - return clean 401 for bad tokens (not 500)

Run from the folder that contains manage.py:
    python harden_google_auth.py

Safe to run more than once. Backs up every edited file first.
"""

import os
import sys
import shutil
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
STAMP = datetime.now().strftime("%Y%m%d-%H%M%S")
BACKUP = HERE / f".google_harden_backup_{STAMP}"

DEFAULT_CLIENT_ID = "488596909366-vd5s2k861kn6g1v8e8f3u81eig3h2q2c.apps.googleusercontent.com"


def find_file(rel_parts, label):
    """Direct path first; fall back to a walk that SKIPS hidden dirs."""
    direct = HERE.joinpath(*rel_parts)
    if direct.is_file():
        return direct
    suffix = os.path.join(*rel_parts)  # e.g. accounts/api/views.py
    target = rel_parts[-1]
    for root, dirs, files in os.walk(HERE):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        if target in files:
            cand = Path(root) / target
            if str(cand).endswith(suffix):
                return cand
    return None


SETTINGS = find_file(["agricore_project", "settings.py"], "settings.py")
VIEWS = find_file(["accounts", "api", "views.py"], "accounts/api/views.py")

if not SETTINGS or not VIEWS:
    print("ERROR: could not locate target files.")
    print("  settings.py:", SETTINGS)
    print("  views.py   :", VIEWS)
    print("Run this from the folder that contains manage.py.")
    sys.exit(1)


# ---------------------------------------------------------------- settings.py
SETTINGS_BLOCK = (
    "\n"
    "# Google OAuth: client IDs accepted as ID-token audiences (Android / iOS / web).\n"
    "# Set GOOGLE_OAUTH_CLIENT_IDS in .env as a comma-separated list to override.\n"
    "GOOGLE_OAUTH_CLIENT_IDS = env.list(\n"
    "    'GOOGLE_OAUTH_CLIENT_IDS',\n"
    f"    default=['{DEFAULT_CLIENT_ID}'],\n"
    ")\n"
)


def patch_settings(text):
    if "GOOGLE_OAUTH_CLIENT_IDS" in text:
        return text, "skip (already present)"
    lines = text.split("\n")
    anchor_idx = None
    for i, ln in enumerate(lines):
        if ln.startswith("PAYMENT_REDIRECT_URL"):
            anchor_idx = i
            break
    if anchor_idx is None:
        raise RuntimeError("settings.py: PAYMENT_REDIRECT_URL anchor not found")
    block_lines = SETTINGS_BLOCK.split("\n")
    new_lines = lines[: anchor_idx + 1] + block_lines + lines[anchor_idx + 1 :]
    return "\n".join(new_lines), "patched"


# ---------------------------------------------------------------- views.py
NEW_CLASS = '''class GoogleAuthView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        token = request.data.get('token') or request.data.get('id_token')

        if not token:
            return Response(
                {'error': 'Token is required'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        allowed_auds = getattr(settings, 'GOOGLE_OAUTH_CLIENT_IDS', [])
        if not allowed_auds:
            return Response(
                {'error': 'Google sign-in is not configured on the server'},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        try:
            # Verify signature, issuer, and expiry against Google's public certs.
            # audience=None so we can accept several client IDs (Android / iOS /
            # web) and check the audience ourselves against the allow-list below.
            idinfo = id_token.verify_oauth2_token(
                token,
                requests.Request(),
                audience=None,
            )
        except ValueError as e:
            return Response(
                {'error': f'Invalid token: {str(e)}'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        # The token must have been issued for one of our own apps.
        if idinfo.get('aud') not in allowed_auds:
            return Response(
                {'error': 'Token audience is not allowed'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        # Only accept emails that Google itself has verified.
        if not idinfo.get('email_verified', False):
            return Response(
                {'error': 'Google account email is not verified'},
                status=status.HTTP_403_FORBIDDEN,
            )

        email = idinfo.get('email')
        google_id = idinfo.get('sub', '')
        name = idinfo.get('name', '')

        if not email:
            return Response(
                {'error': 'Email not provided by Google'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Match an existing account by email (links password + Google logins),
        # or create a new one. The email is Google-verified at this point.
        user, created = CustomUser.objects.get_or_create(
            email=email,
            defaults={
                'username': email.split('@')[0] + '_' + google_id[:8],
                'first_name': name.split()[0] if name else '',
                'last_name': ' '.join(name.split()[1:]) if len(name.split()) > 1 else '',
                'is_verified': True,
            },
        )

        # A successful Google login proves email ownership.
        if not user.is_verified:
            user.is_verified = True
            user.save(update_fields=['is_verified'])

        refresh = RefreshToken.for_user(user)

        return Response({
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'user': CustomUserSerializer(user).data,
            'created': created,
        }, status=status.HTTP_200_OK)'''


def patch_views(text):
    if "audience=None" in text and "email_verified" in text:
        return text, "skip (already hardened)"
    lines = text.split("\n")
    # locate the GoogleAuthView class
    start = None
    for i, ln in enumerate(lines):
        if ln.startswith("class GoogleAuthView(APIView):"):
            start = i
            break
    if start is None:
        raise RuntimeError("views.py: 'class GoogleAuthView(APIView):' not found")
    # next top-level class after it
    end = None
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("class "):
            end = i
            break
    if end is None:
        raise RuntimeError("views.py: no class found after GoogleAuthView")
    new_block = NEW_CLASS.split("\n") + ["", ""]  # two blank lines before next class
    new_lines = lines[:start] + new_block + lines[end:]
    return "\n".join(new_lines), "patched"


# ---------------------------------------------------------------- run (all-or-nothing)
def main():
    targets = [(SETTINGS, patch_settings), (VIEWS, patch_views)]
    results = []  # (path, new_text, status, changed)

    for path, fn in targets:
        original = path.read_text()
        new_text, st = fn(original)
        changed = new_text != original
        results.append((path, new_text, st, changed))

    if not any(changed for _, _, _, changed in results):
        for path, _, st, _ in results:
            print(f"[skip] {path.relative_to(HERE)}  ->  {st}")
        print("\nNothing to do — already hardened.")
        return

    BACKUP.mkdir(exist_ok=True)
    for path, new_text, st, changed in results:
        if changed:
            shutil.copy2(path, BACKUP / path.name)
            path.write_text(new_text)
            print(f"[edit] {path.relative_to(HERE)}  ->  {st}  (backup: {BACKUP.name}/{path.name})")
        else:
            print(f"[skip] {path.relative_to(HERE)}  ->  {st}")

    print("\nDone. The hardened Google sign-in endpoint is unchanged in shape:")
    print("  POST /api/auth/google/   body: {\"token\": \"<google id token>\"}")
    print("\nOptional: add this to .env to set client IDs without touching code")
    print("  GOOGLE_OAUTH_CLIENT_IDS=<android-id>,<ios-id>,<web-id>")
    print("\nNext:")
    print("  python manage.py check")


if __name__ == "__main__":
    main()
