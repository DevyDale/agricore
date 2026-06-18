#!/usr/bin/env bash
# Agricore Chats — modern visual refresh + compact WhatsApp-style conversation rows.
set -uo pipefail
if [ ! -f templates/chats.html ]; then echo "X Run from project root (needs templates/chats.html)."; exit 1; fi
BK="redesign_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/chats.html "$BK/templates/chats.html"
echo ">> Backup: $BK/templates/chats.html"
TMP=".redesign_tmp"; mkdir -p "$TMP"

cat > "$TMP/redesign.css" << 'RCSS_EOF'
        /* ===== redesign v1: compact list + modern polish ===== */
        #conversations-list > * + * { margin-top: 0 !important; }
        .conversation-card{ display:flex; align-items:center; gap:.7rem; padding:.55rem .55rem; margin:0; border:none; border-radius:.7rem; box-shadow:none; background:transparent; border-bottom:1px solid #efe8da; transition:background .15s; cursor:pointer; }
        .conversation-card:hover{ transform:none; box-shadow:none; background:#f3f7f1; border-color:transparent; }
        .conversation-card.active{ background:linear-gradient(135deg,#eaf7ec,#dcf0e0); border-color:transparent; box-shadow:none; }
        .conv-av{ position:relative; flex-shrink:0; }
        .conv-av .avatar{ box-shadow:none; }
        .conv-dot{ position:absolute; right:1px; bottom:1px; width:12px; height:12px; border-radius:50%; background:#22c55e; border:2.5px solid #fffdf8; }
        .conv-main{ flex:1; min-width:0; }
        .conv-r1{ display:flex; align-items:baseline; justify-content:space-between; gap:.5rem; }
        .conv-name{ flex:1; min-width:0; font-weight:600; font-size:.92rem; color:var(--ink); }
        .conv-time{ font-size:.68rem; color:var(--muted); flex-shrink:0; }
        .conv-r2{ font-size:.78rem; color:var(--muted); margin-top:.05rem; }
        .conv-r2.online{ color:#16a34a; font-weight:600; }
        .sidebar, .chat-room{ box-shadow:0 8px 30px rgba(60,46,20,.07); }
        .tabs{ background:#f1ece1; }
        .tab-btn.active{ box-shadow:0 1px 4px rgba(60,46,20,.12); }
RCSS_EOF

cat > "$TMP/new_tile.txt" << 'NTILE_EOF'
function renderConvTile(c){
  const dn = c.display_name || c.title || 'Conversation';
  const initials = (dn.replace(/[^A-Za-z0-9 ]/g,'').trim().split(/\s+/).map(s=>s[0]||'').join('').slice(0,2).toUpperCase())||'C';
  const online = c.type==='direct' && c.other_online;
  let sub, subCls='';
  if (c.type==='direct'){
    if (online){ sub='Active now'; subCls='online'; }
    else sub = c.other_last_seen ? ('last seen '+fmtAgo(new Date(c.other_last_seen))) : 'offline';
  } else {
    sub = (c.type==='channel'?'Channel':'Group')+' · '+(c.participant_count||0)+' members';
  }
  const active = currentConversationId===c.id ? 'active' : '';
  const time = c.updated_at ? fmtAgo(new Date(c.updated_at)) : '';
  return '<div class="conversation-card '+active+'" data-id="'+c.id+'" data-name="'+escH(dn)+'" data-admin="'+(c.my_role==='admin'?'1':'0')+'">'
    + '<div class="conv-av"><div class="avatar" style="width:46px;height:46px;background:linear-gradient(135deg,'+(online?'#10b981':'#94a3b8')+','+(online?'#059669':'#64748b')+')">'+initials+'</div>'+(online?'<span class="conv-dot"></span>':'')+'</div>'
    + '<div class="conv-main"><div class="conv-r1"><span class="conv-name truncate">'+escH(dn)+'</span><span class="conv-time">'+time+'</span></div>'
    + '<div class="conv-r2 truncate '+subCls+'">'+escH(sub)+'</div></div></div>';
}
NTILE_EOF

cat > "$TMP/old_tile.txt" << 'OTILE_EOF'
function renderConvTile(c){
  const dn = c.display_name || c.title || 'Conversation';
  const initials = (dn.replace(/[^A-Za-z0-9 ]/g,'').trim().split(/\s+/).map(s=>s[0]||'').join('').slice(0,2).toUpperCase())||'C';
  let sub;
  if (c.type==='direct'){
    sub = c.other_online ? '<span class="text-green-600 text-xs font-semibold"><span class="inline-block w-2 h-2 bg-green-500 rounded-full mr-1.5"></span>Active now</span>'
        : '<span class="text-gray-500 text-xs">'+(c.other_last_seen?('last seen '+fmtAgo(new Date(c.other_last_seen))):'offline')+'</span>';
  } else {
    sub = '<span class="text-gray-500 text-xs">'+typeBadge(c.type)+' · '+(c.participant_count||0)+' members</span>';
  }
  const active = currentConversationId===c.id ? 'active' : '';
  const online = c.type==='direct' && c.other_online;
  return '<div class="conversation-card '+active+'" data-id="'+c.id+'" data-name="'+escH(dn)+'" data-admin="'+(c.my_role==='admin'?'1':'0')+'">'
    + '<div class="flex items-center gap-3">'
    + '<div class="avatar" style="background:linear-gradient(135deg,'+(online?'#10b981':'#94a3b8')+','+(online?'#059669':'#64748b')+')">'+initials+'</div>'
    + '<div class="flex-1 min-w-0"><h3 class="text-sm font-bold text-gray-800 truncate">'+escH(dn)+'</h3>'
    + '<p class="text-xs text-gray-500 truncate mt-0.5">'+sub+'</p></div></div></div>';
}
OTILE_EOF

cat > "$TMP/apply_redesign.py" << 'RPY_EOF'
import sys
PATH='templates/chats.html'
s=open(PATH,encoding='utf-8').read()
if '/* ===== redesign v1' in s:
    print('   - redesign already applied'); sys.exit(0)
css=open('redesign.css',encoding='utf-8').read()
old=open('old_tile.txt',encoding='utf-8').read().rstrip()
new=open('new_tile.txt',encoding='utf-8').read().rstrip()
i=s.find('</style>')
if i<0: print('   X no </style>'); sys.exit(1)
s=s[:i]+css+'\n'+s[i:]
if old not in s:
    print('   X renderConvTile anchor not found -> untouched'); sys.exit(1)
s=s.replace(old,new,1)
open(PATH,'w',encoding='utf-8').write(s)
print('   OK redesign applied')
RPY_EOF

cp "$TMP"/redesign.css "$TMP"/new_tile.txt "$TMP"/old_tile.txt "$TMP"/apply_redesign.py .
python3 apply_redesign.py; RC=$?
rm -f redesign.css new_tile.txt old_tile.txt apply_redesign.py; rm -rf "$TMP"
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/templates/chats.html templates/chats.html"; exit 1; fi
if command -v node >/dev/null 2>&1; then
  python3 - << 'CHK'
import re;s=open('templates/chats.html').read()
m=re.search(r'<script>\n(/\* ===== Agricore Chats.*?)\n    </script>',s,re.S)
open('.chk.js','w').write(m.group(1) if m else 'throw 0')
CHK
  node --check .chk.js && echo ">> JS OK" || echo ">> WARNING JS check failed"; rm -f .chk.js
fi
echo ">> Done. Hard-refresh chats.html. Rollback: cp -a $BK/templates/chats.html templates/chats.html"
