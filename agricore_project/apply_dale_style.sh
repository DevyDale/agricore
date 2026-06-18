#!/usr/bin/env bash
# Dale AI -> concise, professional replies (rewrites the system prompt in ai/api/views.py).
# One endpoint governs Dale on every page, so this fixes the verbose-tables problem everywhere.
set -uo pipefail
if [ ! -f ai/api/views.py ]; then echo "X Run from the Django project root (the folder with manage.py / the ai app)."; exit 1; fi
if [ ! -f manage.py ]; then echo "Note: manage.py not seen here; make sure ai/api/views.py is the AI app's views."; fi

BK="dale_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/ai/api"; cp ai/api/views.py "$BK/ai/api/views.py"
echo ">> Backup: $BK/ai/api/views.py"

# optional: isolate on a branch off dev if this is a git repo
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  git checkout -b feature/dale-style 2>/dev/null || echo "   (branch feature/dale-style exists or skipped; continuing)"
fi

cat > .dale.py << 'DALE_PY_EOF'
import sys, ast, re
PATH='ai/api/views.py'
s=open(PATH,encoding='utf-8').read()
if 'Dale AI v2 style' in s:
    print('   - Dale style already updated'); sys.exit(0)

NEW = '''system_msg = (
            "You are Dale, the assistant for Agricore, a farming marketplace and farm-management platform. "
            "Talk like a sharp, friendly professional speaking to a busy person. Lead with the answer or recommendation in the very first sentence. "
            "Keep replies short: 2-4 sentences, or at most 3-5 tight bullet points. No walls of text, no filler, no restating the question, no preamble. "
            "Do NOT use big tables or multi-column breakdowns unless the user explicitly asks to compare items; even then keep it to the few columns that matter. "
            "When recommending, give 1-3 specific picks, each with a one-line reason grounded in the price/rating/stock numbers in the context 'extras'. "
            "If the user asks which one to buy, commit to a single clear best pick and say why in one sentence. "
            "Answer how-to or 'what can I do here' questions using the 'features' text in the context. "
            "Be warm but efficient; skip sign-offs like 'let me know if you want more' unless it genuinely adds value. Only assist the authenticated user."
        )  # Dale AI v2 style'''

pat = re.compile(r'system_msg = \(.*?\n        \)', re.S)
m = pat.search(s)
if not m:
    print('   X system_msg block not found -> file untouched'); sys.exit(1)
s = s[:m.start()] + NEW + s[m.end():]

try:
    ast.parse(s)
except SyntaxError as e:
    print('   X edit would break Python syntax, aborting:', e); sys.exit(1)

open(PATH,'w',encoding='utf-8').write(s)
print('   OK Dale system prompt rewritten for concise, professional replies')
DALE_PY_EOF
python3 .dale.py; RC=$?
rm -f .dale.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/ai/api/views.py ai/api/views.py"; exit 1; fi
echo ">> Now run:  python manage.py check   then restart your server."
echo ">> Rollback: cp -a $BK/ai/api/views.py ai/api/views.py"
