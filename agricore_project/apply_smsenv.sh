#!/usr/bin/env bash
set -euo pipefail

TARGET="agricore_project/settings.py"

BR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
if [ -n "$BR" ] && [ "$BR" != "dev" ]; then
  echo ">> Refusing: current branch is '$BR', not 'dev'."
  exit 1
fi

if [ ! -f "$TARGET" ]; then
  echo ">> Not found: $TARGET"
  echo "   Run this from the Django root:  cd ~/Downloads/projects/agricore/agricore_project"
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
BK="smsenv_backup_${TS}"
mkdir -p "$BK"
cp -a "$TARGET" "$BK/settings.py"
echo ">> Backup: ${BK}/settings.py"

set +e
python3 - "$TARGET" <<'PYEOF'
import sys, ast
path = sys.argv[1]
src = open(path, encoding="utf-8").read()
SENT = "# --- Agricore SMS env (idempotent) ---"
if SENT in src:
    print("   already applied: SMS env block present, no change")
    sys.exit(0)
if "import os" not in src:
    print("   ERROR: settings.py does not import os; aborting (no change made)")
    sys.exit(3)
block = (
    "\n" + SENT + "\n"
    "SMS_PROVIDER = os.environ.get('SMS_PROVIDER', 'console')\n"
    "AT_USERNAME  = os.environ.get('AT_USERNAME', 'sandbox')\n"
    "AT_API_KEY   = os.environ.get('AT_API_KEY', '')\n"
    "AT_SENDER_ID = os.environ.get('AT_SENDER_ID', '')\n"
)
new = src.rstrip("\n") + "\n" + block
try:
    ast.parse(new)
except SyntaxError as e:
    print("   ERROR: result would not parse (%s); aborting" % e)
    sys.exit(2)
open(path, "w", encoding="utf-8").write(new)
print("   OK settings.py: SMS_PROVIDER / AT_USERNAME / AT_API_KEY / AT_SENDER_ID now read from .env")
PYEOF
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  echo ">> Patch failed (rc=${rc}). Restoring backup."
  cp -a "$BK/settings.py" "$TARGET"
  exit "$rc"
fi

echo "DONE"
echo
echo ">> Restart the server (or it auto-reloads), then verify the key is live:"
echo "     python manage.py shell -c \"from django.conf import settings; print(settings.SMS_PROVIDER, settings.AT_USERNAME, settings.AT_API_KEY[:9])\""
echo ">> Rollback: cp -a ${BK}/settings.py ${TARGET}"
