#!/usr/bin/env bash
# ============================================================================
# Phase 1 hotfix — repair accounts/api/views.py after the import-anchor collision.
# Restores that ONE file from the most recent phase1 backup, then re-applies the
# user-search action in a collision-proof way. Run from the Django project root.
# ============================================================================
set -uo pipefail

if [ ! -f manage.py ]; then
  echo "X  Run from your Django project root (folder with manage.py)."; exit 1
fi

BK=$(ls -dt phase1_backup_* 2>/dev/null | head -1)
if [ -z "${BK:-}" ] || [ ! -f "${BK}/accounts/api/views.py" ]; then
  echo "X  No phase1 backup of accounts/api/views.py found. Tell me and I'll work from your current file."
  exit 1
fi
echo ">> Restoring accounts/api/views.py from ${BK}"
cp "${BK}/accounts/api/views.py" accounts/api/views.py

python3 - << 'PYEOF'
path = "accounts/api/views.py"
with open(path) as fh:
    src = fh.read()

# 1) make `action` importable: insert right after the LAST top-of-file import line
if "from rest_framework.decorators import action" not in src:
    lines = src.splitlines(keepends=True)
    insert_at = 0
    for i, ln in enumerate(lines):
        s = ln.strip()
        if s.startswith("import ") or s.startswith("from "):
            insert_at = i + 1
        elif s and not s.startswith("#"):
            break
    lines.insert(insert_at, "from rest_framework.decorators import action\n")
    src = "".join(lines)

# 2) add the search action after get_permissions; Q is imported locally (no module-level edit)
anchor = "        return [IsAuthenticated()]  # Require auth for other actions"
addition = (
    "        return [IsAuthenticated()]  # Require auth for other actions\n\n"
    "    @action(detail=False, methods=['get'], url_path='search')\n"
    "    def search(self, request):\n"
    "        from django.db.models import Q\n"
    "        q = (request.query_params.get('q') or '').strip()\n"
    "        results = []\n"
    "        if q:\n"
    "            qs = (CustomUser.objects\n"
    "                  .filter(Q(username__icontains=q) | Q(email__icontains=q))\n"
    "                  .exclude(id=request.user.id)[:20])\n"
    "            results = [{'id': u.id, 'username': u.username} for u in qs]\n"
    "        return Response(results)"
)
if "url_path='search'" not in src:
    if anchor in src:
        src = src.replace(anchor, addition, 1)
    else:
        print("   X get_permissions anchor not found — paste your CustomUserViewSet and I'll adjust.")

with open(path, "w") as fh:
    fh.write(src)
print("   OK accounts/api/views.py repaired")
PYEOF

echo ">> Syntax check:"
python3 -c "import ast; ast.parse(open('accounts/api/views.py').read())" && echo "   ok" || { echo "   FAILED"; exit 1; }

echo ">> Django check:"
python manage.py check
echo ">> makemigrations (expect 'No changes detected'):"
python manage.py makemigrations --check --dry-run
echo ">> Tests:"
python manage.py test communications accounts --keepdb
