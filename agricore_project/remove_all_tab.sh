#!/usr/bin/env bash
# Removes the "All" tab from chats.html and makes "Inbox" the default. Reversible.
set -uo pipefail
if [ ! -f templates/chats.html ]; then echo "X Run from project root (needs templates/chats.html)."; exit 1; fi
BK="tabs_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/chats.html "$BK/templates/chats.html"
echo ">> Backup: $BK/templates/chats.html"

python3 - << 'PYEOF'
import sys
PATH='templates/chats.html'
s=open(PATH, encoding='utf-8').read()
if 'data-tab="all"' not in s:
    print('   - "All" tab already removed, nothing to do'); sys.exit(0)
edits=[
    ('                        <button class="tab-btn active" data-tab="all">All</button>\n', ''),
    ('                        <button class="tab-btn" data-tab="direct">Inbox</button>',
     '                        <button class="tab-btn active" data-tab="direct">Inbox</button>'),
    ("let currentTab = 'all';", "let currentTab = 'direct';"),
]
for old,new in edits:
    if old not in s:
        print('   X anchor not found -> file left untouched (backup safe):', repr(old[:50])); sys.exit(1)
    s=s.replace(old,new,1)
open(PATH,'w',encoding='utf-8').write(s)
print('   OK removed "All" tab; "Inbox" is now the default')
PYEOF

echo ">> Done. Hard-refresh chats.html (Cmd-Shift-R). Rollback: cp -a $BK/templates/chats.html templates/chats.html"
