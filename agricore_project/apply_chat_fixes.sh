#!/usr/bin/env bash
# Agricore Chats — UI fixes: single-line tabs, Discover moved to header,
# expired session -> authentication.html, redesigned chat bubbles/room.
set -uo pipefail
if [ ! -f templates/chats.html ]; then echo "X Run from project root (needs templates/chats.html)."; exit 1; fi
BK="chatfix_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/chats.html "$BK/templates/chats.html"
echo ">> Backup: $BK/templates/chats.html"

cat > .chatfix.py << 'FIX_PY_EOF'
import sys
PATH='templates/chats.html'
s=open(PATH,encoding='utf-8').read()
if '/* ===== chatroom polish v2' in s:
    print('   - fixes already applied'); sys.exit(0)

CSS = '''        /* ===== chatroom polish v2 ===== */
        .tabs{ display:flex; gap:.3rem; }
        .tab-btn{ flex:1; white-space:nowrap; }
        #discover-btn{ display:inline-flex; align-items:center; gap:.35rem; font-size:.72rem; font-weight:600; padding:.3rem .7rem; border-radius:999px; background:var(--parch); color:#5a5346; border:1px solid var(--line); cursor:pointer; }
        #discover-btn.on{ background:var(--g600); color:#fff; border-color:var(--g600); }
        #discover-btn i{ font-size:.8rem; }
        .chat-body{ padding:1rem 1.25rem; }
        .message-list{ border:none; background:transparent; padding:.4rem .2rem; box-shadow:none; }
        .message-bubble{ padding:.45rem .65rem .3rem; border-radius:1rem; max-width:70%; min-width:54px; box-shadow:0 1px 2px rgba(60,46,20,.08); }
        .message-mine{ border-bottom-right-radius:.35rem; }
        .message-theirs{ border-bottom-left-radius:.35rem; }
        .msg-name{ font-size:.72rem; font-weight:700; color:var(--g700); margin:0 0 .15rem; }
        .message-mine .msg-name{ color:#bbf7d0; }
        .msg-text{ font-size:.9rem; line-height:1.35; white-space:pre-wrap; word-break:break-word; }
        .msg-meta{ display:flex; align-items:center; justify-content:flex-end; gap:.35rem; margin-top:.05rem; line-height:1; }
        .msg-time{ font-size:.6rem; opacity:.75; }
        .message-mine .msg-time{ color:rgba(255,255,255,.85); }
        .message-theirs .msg-time{ color:var(--muted); }
        .rx-pill{ font-size:.6rem; background:rgba(0,0,0,.08); border-radius:999px; padding:.02rem .35rem; }
        .message-mine .rx-pill{ background:rgba(255,255,255,.2); }
        #reply-bar{ background:#eef7f0!important; }
'''

HEADER_TABS = '''                <div class="flex items-center justify-between mb-4">
                    <h2 class="panel-title text-lg font-bold" style="color:var(--ink);">Messages</h2>
                    <div class="flex items-center gap-2">
                        <button id="discover-btn"><i class="fas fa-compass"></i><span id="discover-label">Discover</span></button>
                        <span id="conv-count" class="text-xs font-semibold text-green-800 bg-green-50 px-2.5 py-1 rounded-full border border-green-100">Loading…</span>
                    </div>
                </div>
                <div class="tabs" style="margin:0 0 1rem;">
                    <button class="tab-btn active" data-tab="direct">Inbox</button>
                    <button class="tab-btn" data-tab="groups">Groups</button>
                    <button class="tab-btn" data-tab="channels">Channels</button>
                </div>
                '''

RENDER_MSG = '''function reactionPills(m){
  const r=m.reactions||{like:0,dislike:0,mine:null};
  let out='';
  if(r.like>0) out+='<span class="rx-pill'+(r.mine==='like'?' on':'')+'">\\uD83D\\uDC4D '+r.like+'</span>';
  if(r.dislike>0) out+='<span class="rx-pill'+(r.mine==='dislike'?' on':'')+'">\\uD83D\\uDC4E '+r.dislike+'</span>';
  return out;
}

function renderMessage(m){
  const mine=isMine(m);
  const showName = !mine && currentConv && currentConv.type!=='direct';
  const reply = m.reply_preview ? '<div class="reply-quote">'+escH(m.reply_preview.sender_name)+': '+escH(m.reply_preview.snippet)+'</div>' : '';
  let when=''; try{ when=new Date(m.created_at).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'}); }catch(e){}
  const txt = m.content ? '<div class="msg-text">'+escH(m.content)+'</div>' : '';
  return '<div class="flex '+(mine?'justify-end':'justify-start')+'" data-mid="'+m.id+'">'
    + '<div class="message-bubble '+(mine?'message-mine':'message-theirs')+'">'
    + (showName?'<p class="msg-name">'+escH(m.sender_name||'Member')+'</p>':'')
    + reply + txt + attachmentHtml(m)
    + '<div class="msg-meta">'+reactionPills(m)+'<span class="msg-time">'+when+'</span></div>'
    + '</div></div>';
}'''

# 1) CSS
i=s.find('</style>')
if i<0: print('   X no </style>'); sys.exit(1)
s=s[:i]+CSS+s[i:]

# 2) header + tabs (single boundary, robust to All-tab state)
a=s.find('<div class="flex items-center justify-between mb-4">')
b=s.find('<div class="search-wrap mb-4">')
if a<0 or b<0 or b<a: print('   X header/tabs anchors not found'); sys.exit(1)
s=s[:a]+HEADER_TABS+s[b:]

# 3) renderMessage (boundary)
a=s.find('function renderMessage(m){')
b=s.find('function wireMessageGestures(){', a)
if a<0 or b<0 or b<a: print('   X renderMessage bounds not found'); sys.exit(1)
s=s[:a]+RENDER_MSG+'\n\n'+s[b:]

# 4) session expiry -> auth page (required)
old_login='''  if (!token){ list.innerHTML = '<p class="text-center text-sm" style="color:var(--muted);">Please log in to see your conversations.</p>'; return; }'''
if old_login in s:
    s=s.replace(old_login, "  if (!token){ location.href='authentication.html'; return; }", 1)
else:
    print('   ! login-message anchor not found (skipped)')

# 5) guard initChat (required)
if 'function initChat(){' in s and "initChat guard" not in s:
    s=s.replace('function initChat(){\n', "function initChat(){\n  if(!token){ location.href='authentication.html'; return; } // initChat guard\n", 1)

# 6) discover toggle uses 'on' class (optional)
s=s.replace("document.getElementById('discover-btn').classList.toggle('btn-primary', on);",
            "document.getElementById('discover-btn').classList.toggle('on', on);", 1)

# 7) default tab to direct if still 'all' (optional)
s=s.replace("let currentTab = 'all';", "let currentTab = 'direct';", 1)

open(PATH,'w',encoding='utf-8').write(s)
print('   OK fixes applied')
FIX_PY_EOF
python3 .chatfix.py; RC=$?
rm -f .chatfix.py
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
