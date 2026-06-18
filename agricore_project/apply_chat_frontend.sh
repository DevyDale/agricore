#!/usr/bin/env bash
# ============================================================================
# Agricore Dynamics — Chat UI build (command 2 of 2)
# Surgically upgrades templates/chats.html: type-aware tabs + Discover channels,
# two-green bubbles, sender names, presence/last-seen, long-press menu
# (reply / like / dislike / forward), reactions, replies, multi-media + audio
# recording, members/admin add-remove, delete-with-confirm. Your CSS, the
# farmland header, and the Dale assistant are left untouched.
# Run from the Django project root (folder with manage.py).
# ============================================================================
set -uo pipefail

if [ ! -f manage.py ] || [ ! -f templates/chats.html ]; then
  echo "X  Run from your project root (needs manage.py and templates/chats.html)."; exit 1
fi

STAMP=$(date +%Y%m%d-%H%M%S); BK="chatfrontend_backup_${STAMP}"
mkdir -p "${BK}/templates"; cp templates/chats.html "${BK}/templates/chats.html"
echo ">> Backup: ${BK}/templates/chats.html"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git show-ref --verify --quiet refs/heads/feature/chat-backend; then
    git checkout feature/chat-backend >/dev/null 2>&1 || true
  fi
  echo ">> On branch $(git rev-parse --abbrev-ref HEAD)"
fi

TMP=".chat_v2_tmp"; mkdir -p "$TMP"

cat > "$TMP/new_extra.css" << 'CSS_EOF'
        /* ===== chat feature additions ===== */
        .message-mine { background: linear-gradient(135deg, var(--g600), var(--g900)); color:#fff; margin-left:auto; border-bottom-right-radius:.3rem; }
        .message-theirs { background:#e3f3e6; color:var(--ink); border:1px solid #c7e7cf; border-bottom-left-radius:.3rem; }
        .reply-quote { border-left:3px solid var(--g500); padding:.2rem .5rem; margin-bottom:.35rem; font-size:.78rem; opacity:.9; background:rgba(0,0,0,.05); border-radius:.3rem; }
        .message-mine .reply-quote { background:rgba(255,255,255,.18); border-left-color:#bbf7d0; }
        .rx { display:inline-flex; align-items:center; gap:.25rem; background:none; border:none; cursor:pointer; }
        .message-mine .rx { color:rgba(255,255,255,.85)!important; }
        #msg-menu { position:absolute; z-index:1500; background:#fff; border:1px solid var(--line); border-radius:.75rem; box-shadow:0 12px 30px rgba(20,30,18,.22); padding:.3rem; display:none; min-width:150px; }
        #msg-menu.show { display:block; }
        #msg-menu button { display:flex; align-items:center; gap:.6rem; width:100%; text-align:left; padding:.55rem .7rem; border:none; background:none; border-radius:.5rem; font-size:.875rem; cursor:pointer; color:var(--ink); }
        #msg-menu button:hover { background:var(--parch); }
        #record-btn.recording { background:#ef4444!important; color:#fff!important; border-color:#ef4444!important; animation:recPulse 1s infinite; }
        @keyframes recPulse { 0%,100%{box-shadow:0 0 0 0 rgba(239,68,68,.5);} 50%{box-shadow:0 0 0 7px rgba(239,68,68,0);} }
        #toast { position:fixed; bottom:1.5rem; left:50%; transform:translateX(-50%) translateY(20px); background:#16271c; color:#fff; padding:.7rem 1.2rem; border-radius:.75rem; font-size:.875rem; opacity:0; pointer-events:none; transition:all .25s; z-index:2000; }
        #toast.show { opacity:1; transform:translateX(-50%) translateY(0); }
        .search-wrap #user-search-results { position:absolute; left:0; right:0; z-index:50; }
CSS_EOF

cat > "$TMP/new_main.html" << 'MAIN_EOF'
    <!-- Main Content -->
    <main class="main-container">
        <div class="sidebar glass" id="sidebar">
            <div class="sidebar-content">
                <div class="flex items-center justify-between mb-4">
                    <h2 class="panel-title text-lg font-bold" style="color:var(--ink);">Messages</h2>
                    <span id="conv-count" class="text-xs font-semibold text-green-800 bg-green-50 px-2.5 py-1 rounded-full border border-green-100">Loading…</span>
                </div>
                <div class="flex items-center gap-2 mb-3">
                    <div class="tabs flex-1" style="margin:0;">
                        <button class="tab-btn active" data-tab="all">All</button>
                        <button class="tab-btn" data-tab="direct">Inbox</button>
                        <button class="tab-btn" data-tab="groups">Groups</button>
                        <button class="tab-btn" data-tab="channels">Channels</button>
                    </div>
                    <button id="discover-btn" class="btn-secondary text-xs px-3 py-2 whitespace-nowrap"><i class="fas fa-compass mr-1"></i><span id="discover-label">Discover</span></button>
                </div>
                <div class="search-wrap mb-4">
                    <i class="fas fa-search search-ic"></i>
                    <input type="text" id="conversation-search" placeholder="Search chats, channels &amp; people..." class="input-field" autocomplete="off">
                    <span id="clear-search" class="clear-search"><i class="fas fa-circle-xmark"></i></span>
                    <div id="user-search-results" class="bg-white rounded-lg shadow mt-2 max-h-56 overflow-y-auto hidden" style="border:1px solid var(--line);"></div>
                </div>
                <div id="conversations-list" class="conversations-list space-y-2"></div>
            </div>
        </div>

        <div class="chat-room glass" id="chat-room">
            <div id="chat-placeholder" class="flex-1 flex items-center justify-center p-8" style="color:var(--muted);">
                <div class="text-center">
                    <i class="fas fa-comments text-5xl mb-4" style="color:#d8cdb5;"></i>
                    <p class="panel-title text-lg font-semibold" style="color:#4a4434;">Select a conversation to start chatting</p>
                </div>
            </div>
            <div id="chat-content" class="hidden flex-1 flex flex-col overflow-hidden">
                <div class="chat-header">
                    <div class="flex items-center">
                        <button class="back-btn" id="back-btn"><i class="fas fa-arrow-left" style="color:#5a5346;"></i></button>
                        <h2 id="chat-title" class="text-lg font-bold" style="color:var(--ink);"></h2>
                    </div>
                    <div class="flex items-center gap-2">
                        <div id="presence-indicator" class="text-sm pill px-3 py-1.5 bg-white shadow-sm" style="color:#5a5346;border:1px solid var(--line);"></div>
                        <button id="members-btn" class="hidden btn-secondary text-sm px-3 py-1.5"><i class="fas fa-users"></i></button>
                    </div>
                </div>
                <div class="chat-body">
                    <div id="message-list" class="message-list space-y-4"></div>
                </div>
                <div id="reply-bar" class="hidden" style="padding:.5rem 1.2rem;border-top:1px solid var(--line);background:#f0faf2;display:flex;align-items:center;gap:.6rem;">
                    <i class="fas fa-reply" style="color:var(--g700)"></i>
                    <span id="reply-bar-text" class="text-sm flex-1 truncate" style="color:#4a4434;"></span>
                    <button id="reply-cancel" class="text-gray-500"><i class="fas fa-times"></i></button>
                </div>
                <div class="message-input-area">
                    <div class="message-compose">
                        <label for="image-input" class="px-3 py-2 pill text-sm cursor-pointer flex items-center font-medium" style="background:var(--parch);color:#5a5346;border:1px solid var(--line);"><i class="fas fa-paperclip"></i></label>
                        <input id="image-input" type="file" accept="image/*,video/*,audio/*,.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.txt,.csv" class="hidden">
                        <button id="record-btn" class="px-3 py-2 pill text-sm flex items-center font-medium" style="background:#fffdf8;color:var(--g700);border:1px solid var(--line);"><i class="fas fa-microphone"></i></button>
                        <span id="rec-ready" class="hidden text-xs" style="color:var(--g700);align-self:center;">audio ready</span>
                        <textarea id="message-input" placeholder="Type your message..." class="input-field p-3 text-sm" rows="2"></textarea>
                        <button id="send-message" class="btn-primary px-5 py-3 flex items-center whitespace-nowrap"><i class="fas fa-paper-plane"></i></button>
                    </div>
                </div>
            </div>
        </div>
    </main>

MAIN_EOF

cat > "$TMP/new_modals.html" << 'MOD_EOF'
    <!-- New Conversation Modal -->
    <div id="new-conversation-modal" class="modal">
        <div class="modal-content">
            <h2 class="panel-title text-xl font-bold mb-6" style="color:var(--ink);">Create Group / Channel</h2>
            <div class="space-y-4">
                <div><label class="block text-sm font-semibold mb-2" style="color:#4a4434;">Title</label>
                    <input id="new-conv-title" type="text" class="input-field" placeholder="Enter a name"></div>
                <div><label class="block text-sm font-semibold mb-2" style="color:#4a4434;">Type</label>
                    <select id="new-conv-type" class="input-field">
                        <option value="group">Group — private, you add members</option>
                        <option value="channel">Channel — public, anyone can find &amp; join</option>
                    </select></div>
            </div>
            <div class="flex justify-end gap-3 mt-8">
                <button id="new-conv-cancel" class="btn-secondary px-6 py-2.5">Cancel</button>
                <button id="new-conv-create" class="btn-primary px-6 py-2.5">Create</button>
            </div>
        </div>
    </div>

    <!-- Members / Admin Modal -->
    <div id="members-modal" class="modal">
        <div class="modal-content">
            <h2 class="panel-title text-xl font-bold mb-4" style="color:var(--ink);">Members</h2>
            <div id="member-add-wrap" class="hidden mb-3">
                <input id="member-add-input" class="input-field" placeholder="Search a user to add...">
                <div id="member-add-results" class="mt-1"></div>
            </div>
            <div id="members-list" class="max-h-72 overflow-y-auto"></div>
            <div class="flex justify-end mt-6"><button class="btn-secondary px-6 py-2.5" onclick="document.getElementById('members-modal').classList.remove('show')">Close</button></div>
        </div>
    </div>

    <!-- Forward Modal -->
    <div id="forward-modal" class="modal">
        <div class="modal-content">
            <h2 class="panel-title text-xl font-bold mb-4" style="color:var(--ink);">Forward to…</h2>
            <div id="forward-list" class="max-h-72 overflow-y-auto space-y-1"></div>
            <div class="flex justify-end mt-6"><button class="btn-secondary px-6 py-2.5" onclick="document.getElementById('forward-modal').classList.remove('show')">Cancel</button></div>
        </div>
    </div>

    <!-- Delete Confirm Modal -->
    <div id="delete-modal" class="modal">
        <div class="modal-content" style="max-width:420px;">
            <h2 class="panel-title text-lg font-bold mb-2" style="color:var(--ink);">Delete chat?</h2>
            <p class="text-sm mb-6" style="color:var(--muted);">This permanently deletes &quot;<span id="delete-name" class="font-semibold"></span>&quot; for everyone. This can't be undone.</p>
            <div class="flex justify-end gap-3">
                <button class="btn-secondary px-6 py-2.5" onclick="document.getElementById('delete-modal').classList.remove('show')">Cancel</button>
                <button id="delete-confirm-btn" class="px-6 py-2.5 rounded-lg font-semibold text-white" style="background:#dc2626;">Delete</button>
            </div>
        </div>
    </div>

    <!-- Long-press message menu -->
    <div id="msg-menu"></div>

MOD_EOF

cat > "$TMP/new_chat.js" << 'JS_EOF'
/* ===== Agricore Chats — full feature script ===== */
const token = localStorage.getItem('access_token');
let myUserId = localStorage.getItem('user_id');
let myUsername = null;
let currentConversationId = null;
let currentConv = null;
let currentTab = 'all';
let discoverMode = false;
let replyTo = null;            // {id, sender_name, snippet}
let chatWS = null, chatWSConvId = null;
let renderedMsgIds = new Set();
let mediaRecorder = null, recordedChunks = [], recordedBlob = null;

function escH(v){ return String(v==null?'':v).replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function authH(extra){ return Object.assign({ 'Authorization': 'Bearer ' + token }, extra||{}); }
function fmtAgo(d){
  const s = Math.floor((Date.now()-d.getTime())/1000);
  if (s<60) return 'just now';
  const m=Math.floor(s/60); if (m<60) return m+'m ago';
  const h=Math.floor(m/60); if (h<24) return h+'h ago';
  const dd=Math.floor(h/24); if (dd<7) return dd+'d ago';
  return d.toLocaleDateString();
}
function typeBadge(t){
  const map={direct:'',group:'<i class="fas fa-user-group"></i> Group',channel:'<i class="fas fa-bullhorn"></i> Channel'};
  return map[t]||'';
}

/* ---------- conversation list ---------- */
async function loadConversations(search=''){
  const list = document.getElementById('conversations-list');
  if (!token){ list.innerHTML = '<p class="text-center text-sm" style="color:var(--muted);">Please log in to see your conversations.</p>'; return; }
  if (discoverMode){ return discoverChannels(search); }
  try{
    let url = '/api/conversations/';
    if (search) url += '?search='+encodeURIComponent(search);
    const res = await fetch(url, { headers: authH() });
    if (res.status===401){ localStorage.clear(); location.href='authentication.html'; return; }
    let convs = res.ok ? await res.json() : [];
    convs.sort((a,b)=> new Date(b.updated_at)-new Date(a.updated_at));
    if (search) convs = convs.filter(c => (c.display_name||c.title||'').toLowerCase().includes(search.toLowerCase()));
    convs = convs.filter(c => currentTab==='all' ? true : c.type===currentTab.replace(/s$/,'') );
    const cc = document.getElementById('conv-count');
    if (cc) cc.textContent = convs.length ? convs.length+' chat'+(convs.length===1?'':'s') : 'No chats';
    list.innerHTML = convs.length ? convs.map(renderConvTile).join('') : emptyConvHtml();
    wireConvTiles();
  }catch(e){ console.error(e); list.innerHTML='<p class="text-red-500 text-center text-sm">Failed to load conversations.</p>'; }
}

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
function emptyConvHtml(){
  return '<div class="text-center py-8"><i class="fas fa-comment-slash text-4xl text-gray-200 mb-3"></i>'
    + '<p class="text-gray-600 text-sm font-medium mb-4">No conversations yet.</p>'
    + '<button id="empty-create-btn" class="btn-primary px-4 py-2 text-sm">Create Group / Channel</button></div>';
}
function wireConvTiles(){
  document.querySelectorAll('.conversation-card').forEach(card=>{
    const id = Number(card.dataset.id), name = card.dataset.name, isAdmin = card.dataset.admin==='1';
    card.addEventListener('click', ()=> loadChatRoom(id, name));
    let timer=null;
    const start=()=>{ timer=setTimeout(()=>{ if(isAdmin) confirmDeleteChat(id, name); else toast('Only an admin can delete this chat.'); }, 600); };
    const cancel=()=>{ if(timer){ clearTimeout(timer); timer=null; } };
    card.addEventListener('mousedown', start); card.addEventListener('touchstart', start, {passive:true});
    card.addEventListener('mouseup', cancel); card.addEventListener('mouseleave', cancel);
    card.addEventListener('touchend', cancel); card.addEventListener('touchmove', cancel);
  });
  const ec = document.getElementById('empty-create-btn');
  if (ec) ec.addEventListener('click', ()=> document.getElementById('new-conversation-modal').classList.add('show'));
}

/* ---------- discover public channels ---------- */
async function discoverChannels(search=''){
  const list = document.getElementById('conversations-list');
  try{
    let url='/api/conversations/public/'; if(search) url+='?search='+encodeURIComponent(search);
    const res = await fetch(url, { headers: authH() });
    const chans = res.ok ? await res.json() : [];
    const cc=document.getElementById('conv-count'); if(cc) cc.textContent=chans.length+' channel'+(chans.length===1?'':'s');
    list.innerHTML = chans.length ? chans.map(c=>{
      const dn=c.title||'Channel';
      const initials=(dn.replace(/[^A-Za-z0-9 ]/g,'').trim().split(/\s+/).map(s=>s[0]||'').join('').slice(0,2).toUpperCase())||'C';
      const joined = c.my_role!=null;
      return '<div class="conversation-card"><div class="flex items-center gap-3">'
        +'<div class="avatar" style="background:linear-gradient(135deg,#10b981,#047857)">'+initials+'</div>'
        +'<div class="flex-1 min-w-0"><h3 class="text-sm font-bold text-gray-800 truncate">'+escH(dn)+'</h3>'
        +'<p class="text-xs text-gray-500 truncate">'+escH(c.description||'Public channel')+' · '+(c.participant_count||0)+'</p></div>'
        +(joined?'<button class="btn-secondary text-xs px-3 py-1.5" data-open="'+c.id+'" data-name="'+escH(dn)+'">Open</button>'
                :'<button class="btn-primary text-xs px-3 py-1.5" data-join="'+c.id+'" data-name="'+escH(dn)+'">Join</button>')
        +'</div></div>';
    }).join('') : '<p class="text-center text-sm py-8" style="color:var(--muted);">No public channels found.</p>';
    list.querySelectorAll('[data-join]').forEach(b=> b.addEventListener('click', async ()=>{
      const id=b.dataset.join;
      const res=await fetch('/api/conversations/'+id+'/join/', {method:'POST', headers: authH()});
      if(res.ok){ toggleDiscover(false); loadChatRoom(Number(id), b.dataset.name); } else toast('Could not join.');
    }));
    list.querySelectorAll('[data-open]').forEach(b=> b.addEventListener('click', ()=>{ toggleDiscover(false); loadChatRoom(Number(b.dataset.open), b.dataset.name); }));
  }catch(e){ console.error(e); }
}
function toggleDiscover(on){
  discoverMode = on;
  document.getElementById('discover-btn').classList.toggle('btn-primary', on);
  document.getElementById('discover-label').textContent = on ? 'My chats' : 'Discover';
  loadConversations(document.getElementById('conversation-search').value.trim());
}

/* ---------- people search (existing behaviour) ---------- */
async function searchPeople(q){
  const box=document.getElementById('user-search-results');
  if(!q){ box.classList.add('hidden'); box.innerHTML=''; return; }
  try{
    const res=await fetch('/api/users/search/?q='+encodeURIComponent(q), {headers:authH()});
    let users=res.ok?await res.json():[];
    users=users.filter(u=>String(u.id)!==String(myUserId));
    box.innerHTML = users.length ? ('<div class="px-3 pt-2 pb-1 text-xs font-bold uppercase tracking-wide text-gray-400">People</div>'
      + users.map(u=>'<div class="flex items-center justify-between px-3 py-2 border-b last:border-b-0 hover:bg-green-50"><div class="flex items-center gap-3"><div class="avatar" style="width:32px;height:32px;font-size:1rem;">'+escH((u.username||'U').slice(0,2).toUpperCase())+'</div><span class="font-medium text-gray-800">'+escH(u.username)+'</span></div><button class="btn-primary px-3 py-1.5 text-xs" data-uid="'+u.id+'" data-username="'+escH(u.username)+'">Chat</button></div>').join(''))
      : '<div class="p-3 text-gray-500 text-sm">No people found.</div>';
    box.classList.remove('hidden');
    box.querySelectorAll('[data-uid]').forEach(b=> b.addEventListener('click', ()=> startDirect(b.dataset.uid, b.dataset.username)));
  }catch(e){ box.innerHTML='<div class="p-3 text-red-500 text-sm">Error searching people.</div>'; box.classList.remove('hidden'); }
}
async function startDirect(uid, username){
  try{
    const res=await fetch('/api/conversations/start-direct-chat/', {method:'POST', headers:authH({'Content-Type':'application/json'}), body:JSON.stringify({user:uid})});
    if(!res.ok) throw 0;
    const d=await res.json();
    document.getElementById('user-search-results').classList.add('hidden');
    document.getElementById('conversation-search').value='';
    loadChatRoom(d.id, d.display_name||d.title||username);
    loadConversations();
  }catch(e){ toast('Failed to start chat.'); }
}

/* ---------- chat room ---------- */
async function loadChatRoom(id, title){
  currentConversationId=id;
  document.getElementById('chat-placeholder').classList.add('hidden');
  document.getElementById('chat-content').classList.remove('hidden');
  document.getElementById('chat-title').textContent=title;
  if (window.innerWidth<=768){ document.getElementById('sidebar').classList.add('hidden-mobile'); document.getElementById('chat-room').classList.remove('hidden-mobile'); }
  try{
    const cres=await fetch('/api/conversations/'+id+'/', {headers:authH()});
    currentConv = cres.ok ? await cres.json() : {id, type:'direct'};
  }catch(e){ currentConv={id, type:'direct'}; }
  updateChatHeader();
  try{
    const res=await fetch('/api/messages/?conversation='+id, {headers:authH()});
    if(res.status===401){ localStorage.clear(); location.href='authentication.html'; return; }
    const msgs=res.ok?await res.json():[];
    renderedMsgIds=new Set(msgs.map(m=>m.id));
    renderMessages(msgs);
    ensureWS(id);
  }catch(e){ document.getElementById('message-list').innerHTML='<p class="text-red-500 text-sm text-center">Failed to load messages.</p>'; }
  cancelReply();
  loadConversations(document.getElementById('conversation-search').value.trim());
}

function updateChatHeader(){
  const p=document.getElementById('presence-indicator');
  const adminBtn=document.getElementById('members-btn');
  if(currentConv.type==='direct'){
    p.innerHTML = currentConv.other_online
      ? '<span class="inline-flex items-center"><span class="w-2 h-2 bg-green-500 rounded-full mr-2"></span>Active now</span>'
      : (currentConv.other_last_seen ? 'last seen '+fmtAgo(new Date(currentConv.other_last_seen)) : 'offline');
    adminBtn.classList.add('hidden');
  } else {
    p.innerHTML = typeBadge(currentConv.type)+' · '+(currentConv.participant_count||0)+' members';
    adminBtn.classList.remove('hidden');
  }
}

function renderMessages(msgs){
  const list=document.getElementById('message-list');
  const byDay={};
  msgs.forEach(m=>{ const k=new Date(m.created_at).toDateString(); (byDay[k]=byDay[k]||[]).push(m); });
  const sections=Object.keys(byDay).sort((a,b)=>new Date(a)-new Date(b)).map(day=>{
    const items=byDay[day].map(renderMessage).join('');
    return '<div><div class="text-center text-xs text-gray-500 my-4"><span class="px-3 py-1.5 bg-white rounded-full shadow-sm font-medium">'+day+'</span></div><div class="space-y-3">'+items+'</div></div>';
  });
  list.innerHTML = sections.length ? sections.join('') : '<p class="text-gray-500 text-sm text-center py-8">No messages yet. Start the conversation!</p>';
  list.scrollTop=list.scrollHeight;
  wireMessageGestures();
}

function isMine(m){ return (myUserId && Number(m.sender_id)===Number(myUserId)) || (myUsername && String(m.sender)===String(myUsername)); }

function attachmentHtml(m){
  if(!m.attachment_url) return '';
  const u=escH(m.attachment_url);
  switch(m.message_type){
    case 'image': return '<img src="'+u+'" class="mt-2 max-h-60 rounded-lg shadow" onerror="this.style.display=\'none\'">';
    case 'video': return '<video src="'+u+'" controls class="mt-2 max-h-60 rounded-lg w-full"></video>';
    case 'audio': return '<audio src="'+u+'" controls class="mt-2 w-full"></audio>';
    default: return '<a href="'+u+'" target="_blank" class="mt-2 inline-flex items-center gap-2 text-sm underline"><i class="fas fa-paperclip"></i> Attachment</a>';
  }
}
function reactionsHtml(m){
  const r=m.reactions||{like:0,dislike:0,mine:null};
  const likeOn=r.mine==='like'?'font-bold text-green-700':'text-gray-500';
  const disOn=r.mine==='dislike'?'font-bold text-red-600':'text-gray-500';
  return '<div class="flex items-center gap-3 mt-1 text-xs">'
    +'<button class="rx '+likeOn+'" data-rx="like" data-mid="'+m.id+'"><i class="fas fa-thumbs-up"></i> '+(r.like||0)+'</button>'
    +'<button class="rx '+disOn+'" data-rx="dislike" data-mid="'+m.id+'"><i class="fas fa-thumbs-down"></i> '+(r.dislike||0)+'</button></div>';
}
function renderMessage(m){
  const mine=isMine(m);
  const showName = !mine && currentConv && currentConv.type!=='direct';
  const reply = m.reply_preview ? '<div class="reply-quote">'+escH(m.reply_preview.sender_name)+': '+escH(m.reply_preview.snippet)+'</div>' : '';
  const body = '<p class="text-sm whitespace-pre-wrap break-words">'+escH(m.content||'')+'</p>';
  const when=(()=>{ try{ return new Date(m.created_at).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'});}catch(e){return '';} })();
  return '<div class="flex '+(mine?'justify-end':'justify-start')+'" data-mid="'+m.id+'">'
    + '<div class="message-bubble '+(mine?'message-mine':'message-theirs')+'">'
    + (showName?'<p class="text-xs font-bold mb-1" style="color:var(--g700)">'+escH(m.sender_name||'Member')+'</p>':'')
    + reply + body + attachmentHtml(m)
    + '<div class="flex items-center '+(mine?'justify-end':'')+' gap-2 mt-1 text-xs '+(mine?'text-white/70':'text-gray-500')+'"><span>'+when+'</span></div>'
    + reactionsHtml(m)
    + '</div></div>';
}

function wireMessageGestures(){
  document.querySelectorAll('.rx').forEach(b=> b.addEventListener('click', e=>{ e.stopPropagation(); reactMessage(b.dataset.mid, b.dataset.rx); }));
  document.querySelectorAll('#message-list [data-mid]').forEach(row=>{
    let timer=null;
    const start=()=>{ timer=setTimeout(()=> openMsgMenu(row.dataset.mid), 500); };
    const cancel=()=>{ if(timer){clearTimeout(timer);timer=null;} };
    row.addEventListener('mousedown', start); row.addEventListener('touchstart', start, {passive:true});
    row.addEventListener('mouseup', cancel); row.addEventListener('mouseleave', cancel);
    row.addEventListener('touchend', cancel); row.addEventListener('touchmove', cancel);
  });
}

/* ---------- message action menu ---------- */
function openMsgMenu(mid){
  closeMsgMenu();
  const row=document.querySelector('#message-list [data-mid="'+mid+'"]');
  const menu=document.getElementById('msg-menu');
  const msg=lastMsgCache[mid];
  menu.innerHTML = '<button data-act="reply"><i class="fas fa-reply"></i> Reply</button>'
    + '<button data-act="like"><i class="fas fa-thumbs-up"></i> Like</button>'
    + '<button data-act="dislike"><i class="fas fa-thumbs-down"></i> Dislike</button>'
    + '<button data-act="forward"><i class="fas fa-share"></i> Forward</button>';
  menu.classList.add('show');
  const r=row.getBoundingClientRect();
  menu.style.top=(window.scrollY+r.top-6)+'px';
  menu.style.left=Math.max(8, r.left)+'px';
  menu.querySelectorAll('button').forEach(b=> b.addEventListener('click', ()=>{
    const a=b.dataset.act; closeMsgMenu();
    if(a==='reply') setReply(msg);
    else if(a==='like'||a==='dislike') reactMessage(mid, a);
    else if(a==='forward') openForward(msg);
  }));
}
function closeMsgMenu(){ const m=document.getElementById('msg-menu'); if(m) m.classList.remove('show'); }
document.addEventListener('click', e=>{ if(!e.target.closest('#msg-menu') && !e.target.closest('[data-mid]')) closeMsgMenu(); });

let lastMsgCache={};
async function reactMessage(mid, reaction){
  try{
    const res=await fetch('/api/messages/'+mid+'/react/', {method:'POST', headers:authH({'Content-Type':'application/json'}), body:JSON.stringify({reaction})});
    if(res.ok){ const m=await res.json(); patchMessage(m); }
  }catch(e){}
}
function patchMessage(m){
  lastMsgCache[m.id]=m;
  const row=document.querySelector('#message-list [data-mid="'+m.id+'"]');
  if(row){ const tmp=document.createElement('div'); tmp.innerHTML=renderMessage(m); row.replaceWith(tmp.firstChild); wireMessageGestures(); }
}

/* ---------- reply ---------- */
function setReply(m){ replyTo={id:m.id, sender_name:m.sender_name, snippet:(m.content||'')||'['+m.message_type+']'};
  document.getElementById('reply-bar').classList.remove('hidden');
  document.getElementById('reply-bar-text').textContent='Replying to '+(m.sender_name||'message')+': '+replyTo.snippet.slice(0,60);
  document.getElementById('message-input').focus();
}
function cancelReply(){ replyTo=null; const b=document.getElementById('reply-bar'); if(b) b.classList.add('hidden'); }

/* ---------- forward ---------- */
async function openForward(m){
  const modal=document.getElementById('forward-modal');
  const listEl=document.getElementById('forward-list');
  modal.classList.add('show');
  listEl.innerHTML='<p class="text-sm text-gray-500 p-3">Loading…</p>';
  const res=await fetch('/api/conversations/', {headers:authH()});
  const convs=res.ok?await res.json():[];
  listEl.innerHTML=convs.map(c=>'<button class="w-full text-left px-3 py-2 rounded-lg hover:bg-green-50 flex items-center gap-2" data-dest="'+c.id+'"><i class="fas fa-comment text-green-600"></i> '+escH(c.display_name||c.title)+'</button>').join('');
  listEl.querySelectorAll('[data-dest]').forEach(b=> b.addEventListener('click', async ()=>{
    const dest=b.dataset.dest;
    const fd=new FormData(); fd.append('conversation', dest);
    let content=m.content||'';
    if(m.attachment_url) content=(content?content+'\n':'')+m.attachment_url;
    fd.append('content', content||'[forwarded]');
    await fetch('/api/messages/', {method:'POST', headers:authH(), body:fd});
    modal.classList.remove('show'); toast('Forwarded.');
  }));
}

/* ---------- sending ---------- */
async function sendMessage(){
  if(!currentConversationId) return toast('Pick a conversation first.');
  const input=document.getElementById('message-input');
  const fileIn=document.getElementById('image-input');
  const content=input.value.trim();
  const hasFile=(fileIn.files&&fileIn.files.length)||recordedBlob;
  if(!content && !hasFile) return;
  const fd=new FormData();
  fd.append('conversation', currentConversationId);
  if(content) fd.append('content', content);
  if(replyTo) fd.append('reply_to', replyTo.id);
  if(recordedBlob) fd.append('attachment', recordedBlob, 'audio_'+Date.now()+'.webm');
  else if(fileIn.files&&fileIn.files.length) fd.append('attachment', fileIn.files[0]);
  try{
    const res=await fetch('/api/messages/', {method:'POST', headers:authH(), body:fd});
    if(res.status===401){ localStorage.clear(); location.href='authentication.html'; return; }
    if(!res.ok) throw 0;
    input.value=''; fileIn.value=''; recordedBlob=null; updateRecUI(false); cancelReply();
    const m=await res.json(); if(m && m.id){ renderedMsgIds.add(m.id); appendMessage(m); }
  }catch(e){ toast('Failed to send.'); }
}
function appendMessage(m){
  lastMsgCache[m.id]=m;
  const list=document.getElementById('message-list');
  if(list.querySelector('.text-center')&&!list.querySelector('[data-mid]')) list.innerHTML='';
  const tmp=document.createElement('div'); tmp.innerHTML=renderMessage(m);
  list.appendChild(tmp.firstChild); list.scrollTop=list.scrollHeight; wireMessageGestures();
}

/* ---------- audio recording ---------- */
async function toggleRecord(){
  if(mediaRecorder && mediaRecorder.state==='recording'){ mediaRecorder.stop(); return; }
  if(!navigator.mediaDevices || !window.MediaRecorder){ return toast('Recording not supported here.'); }
  try{
    const stream=await navigator.mediaDevices.getUserMedia({audio:true});
    recordedChunks=[]; mediaRecorder=new MediaRecorder(stream);
    mediaRecorder.ondataavailable=e=>{ if(e.data.size) recordedChunks.push(e.data); };
    mediaRecorder.onstop=()=>{ recordedBlob=new Blob(recordedChunks, {type:'audio/webm'}); stream.getTracks().forEach(t=>t.stop()); updateRecUI(false, true); };
    mediaRecorder.start(); updateRecUI(true);
  }catch(e){ toast('Mic permission denied.'); }
}
function updateRecUI(recording, ready){
  const b=document.getElementById('record-btn');
  b.classList.toggle('recording', !!recording);
  b.innerHTML = recording ? '<i class="fas fa-stop"></i>' : '<i class="fas fa-microphone"></i>';
  const tag=document.getElementById('rec-ready');
  if(tag) tag.classList.toggle('hidden', !ready);
}

/* ---------- members / admin ---------- */
async function openMembers(){
  if(!currentConv || currentConv.type==='direct') return;
  const modal=document.getElementById('members-modal');
  modal.classList.add('show');
  const res=await fetch('/api/conversations/'+currentConversationId+'/members/', {headers:authH()});
  const members=res.ok?await res.json():[];
  const amAdmin=currentConv.my_role==='admin';
  document.getElementById('members-list').innerHTML=members.map(p=>{
    const pres = p.online ? '<span class="text-green-600 text-xs">● active</span>' : '<span class="text-gray-400 text-xs">'+(p.last_seen?('seen '+fmtAgo(new Date(p.last_seen))):'offline')+'</span>';
    const role = p.role==='admin' ? '<span class="text-xs font-bold" style="color:var(--g700)">Admin</span>' : '';
    const rm = (amAdmin && p.role!=='admin') ? '<button class="text-red-500 text-xs" data-remove="'+p.user+'">Remove</button>' : '';
    return '<div class="flex items-center justify-between py-2 border-b"><div><div class="font-medium text-gray-800">'+escH(p.username)+' '+role+'</div>'+pres+'</div>'+rm+'</div>';
  }).join('');
  document.getElementById('member-add-wrap').classList.toggle('hidden', !amAdmin);
  document.getElementById('members-list').querySelectorAll('[data-remove]').forEach(b=> b.addEventListener('click', async ()=>{
    await fetch('/api/conversations/'+currentConversationId+'/remove-member/', {method:'POST', headers:authH({'Content-Type':'application/json'}), body:JSON.stringify({user:b.dataset.remove})});
    openMembers(); loadChatRoom(currentConversationId, document.getElementById('chat-title').textContent);
  }));
}
async function memberAddSearch(q){
  const box=document.getElementById('member-add-results'); if(!q){ box.innerHTML=''; return; }
  const res=await fetch('/api/users/search/?q='+encodeURIComponent(q), {headers:authH()});
  const users=res.ok?await res.json():[];
  box.innerHTML=users.map(u=>'<button class="block w-full text-left px-2 py-1.5 hover:bg-green-50 rounded text-sm" data-add="'+u.id+'">'+escH(u.username)+'</button>').join('');
  box.querySelectorAll('[data-add]').forEach(b=> b.addEventListener('click', async ()=>{
    await fetch('/api/conversations/'+currentConversationId+'/add-member/', {method:'POST', headers:authH({'Content-Type':'application/json'}), body:JSON.stringify({user:b.dataset.add})});
    document.getElementById('member-add-input').value=''; box.innerHTML=''; openMembers();
  }));
}

/* ---------- delete chat ---------- */
function confirmDeleteChat(id, name){
  const modal=document.getElementById('delete-modal');
  modal.classList.add('show');
  document.getElementById('delete-name').textContent=name;
  const btn=document.getElementById('delete-confirm-btn');
  btn.disabled=false; btn.innerHTML='Delete';
  btn.onclick=async ()=>{
    btn.disabled=true; btn.innerHTML='<i class="fas fa-spinner fa-spin"></i> Deleting…';
    try{
      const res=await fetch('/api/conversations/'+id+'/', {method:'DELETE', headers:authH()});
      if(res.status===403){ toast('Only an admin can delete this chat.'); }
      else if(!res.ok && res.status!==204) throw 0;
      else { if(currentConversationId===id){ currentConversationId=null; document.getElementById('chat-content').classList.add('hidden'); document.getElementById('chat-placeholder').classList.remove('hidden'); } }
    }catch(e){ toast('Failed to delete.'); }
    modal.classList.remove('show'); loadConversations();
  };
}

/* ---------- websocket ---------- */
function wsURL(id){ const p=location.protocol==='https:'?'wss':'ws'; return p+'://'+location.host+'/ws/chat/'+id+'/?token='+encodeURIComponent(token||''); }
function ensureWS(id){
  if(!token||id==null) return;
  if(chatWSConvId===id && chatWS && chatWS.readyState===1) return;
  try{ if(chatWS){ chatWS.onclose=null; chatWS.close(); } }catch(e){}
  chatWSConvId=id;
  try{
    chatWS=new WebSocket(wsURL(id));
    chatWS.onmessage=ev=>{ try{ handleWS(JSON.parse(ev.data)); }catch(e){} };
    chatWS.onclose=()=>{ chatWS=null; };
    chatWS.onerror=()=>{ try{ chatWS.close(); }catch(e){} };
  }catch(e){ chatWS=null; }
}
function handleWS(d){
  if(d && d._presence){
    if(currentConv && currentConv.type==='direct'){
      currentConv.other_online=d._presence.online; currentConv.other_last_seen=d._presence.last_seen; updateChatHeader();
    }
    return;
  }
  if(String(chatWSConvId)!==String(currentConversationId)) return;
  if(d && d.id!=null){
    if(d._update){ patchMessage(d); return; }
    if(renderedMsgIds.has(d.id)) return;
    renderedMsgIds.add(d.id); lastMsgCache[d.id]=d; appendMessage(d);
  }
}

/* ---------- misc ui ---------- */
function toast(msg){
  let t=document.getElementById('toast'); if(!t){ t=document.createElement('div'); t.id='toast'; document.body.appendChild(t); }
  t.textContent=msg; t.classList.add('show'); clearTimeout(t._h); t._h=setTimeout(()=>t.classList.remove('show'), 2600);
}

/* ---------- wiring ---------- */
function initChat(){
  const search=document.getElementById('conversation-search');
  const clear=document.getElementById('clear-search');
  let pt=null;
  search.addEventListener('input', ()=>{
    const q=search.value.trim(); clear.style.display=q?'block':'none';
    loadConversations(q);
    if(pt) clearTimeout(pt);
    if(!q){ document.getElementById('user-search-results').classList.add('hidden'); return; }
    pt=setTimeout(()=>searchPeople(q), 300);
  });
  clear.addEventListener('click', ()=>{ search.value=''; clear.style.display='none'; document.getElementById('user-search-results').classList.add('hidden'); loadConversations(''); });

  document.querySelectorAll('.tab-btn').forEach(b=> b.addEventListener('click', ()=>{
    document.querySelectorAll('.tab-btn').forEach(x=>x.classList.remove('active')); b.classList.add('active');
    currentTab=b.dataset.tab; if(discoverMode) toggleDiscover(false); else loadConversations(search.value.trim());
  }));
  document.getElementById('discover-btn').addEventListener('click', ()=> toggleDiscover(!discoverMode));

  document.getElementById('send-message').addEventListener('click', sendMessage);
  document.getElementById('message-input').addEventListener('keydown', e=>{ if(e.key==='Enter'&&!e.shiftKey){ e.preventDefault(); sendMessage(); } });
  document.getElementById('record-btn').addEventListener('click', toggleRecord);
  document.getElementById('reply-cancel').addEventListener('click', cancelReply);
  document.getElementById('members-btn').addEventListener('click', openMembers);
  document.getElementById('back-btn').addEventListener('click', ()=>{ document.getElementById('chat-content').classList.add('hidden'); document.getElementById('chat-placeholder').classList.remove('hidden'); if(window.innerWidth<=768){ document.getElementById('sidebar').classList.remove('hidden-mobile'); document.getElementById('chat-room').classList.add('hidden-mobile'); } });

  const memIn=document.getElementById('member-add-input'); if(memIn){ let mt=null; memIn.addEventListener('input', ()=>{ if(mt)clearTimeout(mt); mt=setTimeout(()=>memberAddSearch(memIn.value.trim()),300); }); }

  // create group/channel
  const modal=document.getElementById('new-conversation-modal');
  document.getElementById('new-conversation-btn').addEventListener('click', ()=> modal.classList.add('show'));
  document.getElementById('new-conv-cancel').addEventListener('click', ()=> modal.classList.remove('show'));
  document.getElementById('new-conv-create').addEventListener('click', async ()=>{
    const title=document.getElementById('new-conv-title').value.trim();
    const type=document.getElementById('new-conv-type').value;
    if(!title) return toast('Enter a title.');
    const body={title, type, is_public: type==='channel'};
    try{
      const res=await fetch('/api/conversations/', {method:'POST', headers:authH({'Content-Type':'application/json'}), body:JSON.stringify(body)});
      if(!res.ok) throw 0;
      const d=await res.json();
      modal.classList.remove('show'); document.getElementById('new-conv-title').value='';
      loadConversations(); loadChatRoom(d.id, d.display_name||d.title||title);
    }catch(e){ toast('Failed to create.'); }
  });

  document.querySelectorAll('.modal').forEach(m=> m.addEventListener('click', e=>{ if(e.target===m) m.classList.remove('show'); }));
  document.getElementById('logout-btn').addEventListener('click', ()=>{ localStorage.removeItem('access_token'); localStorage.removeItem('refresh_token'); location.href='authentication.html'; });

  // mobile nav
  const mb=document.getElementById('mobile-menu-btn'), nav=document.getElementById('header-nav'), ov=document.getElementById('nav-overlay');
  if(mb){ mb.addEventListener('click', ()=>{ nav.classList.toggle('open'); ov.classList.toggle('show'); }); ov.addEventListener('click', ()=>{ nav.classList.remove('open'); ov.classList.remove('show'); }); }

  if(token){
    fetch('/api/users/me/', {headers:authH()}).then(r=>r.ok?r.json():null).then(u=>{ if(u){ if(u.id){ myUserId=u.id; localStorage.setItem('user_id', u.id);} if(u.username) myUsername=u.username; } });
  }
  loadConversations();
}
document.addEventListener('DOMContentLoaded', initChat);
JS_EOF

cat > "$TMP/assemble_chats.py" << 'ASM_EOF'
import sys, os
PATH = 'templates/chats.html'
with open(PATH, encoding='utf-8') as f:
    src = f.read()

def fail(m):
    print('   X ' + m + ' -> file left untouched (backup is safe)')
    sys.exit(1)

if 'id="discover-btn"' in src:
    print('   - chats.html already upgraded, skipping')
    sys.exit(0)

css    = open('new_extra.css', encoding='utf-8').read()
main   = open('new_main.html', encoding='utf-8').read()
modals = open('new_modals.html', encoding='utf-8').read()
js     = open('new_chat.js', encoding='utf-8').read()

# 1) inject feature CSS just before the first </style>
i = src.find('</style>')
if i < 0:
    fail('no </style> found')
src = src[:i] + css + '\n' + src[i:]

# 2) swap the whole <main class="main-container"> region
a = src.find('<!-- Main Content -->')
b = src.find('<!-- New Conversation Modal -->')
if a < 0 or b < 0 or b < a:
    fail('main-content markers not found')
src = src[:a] + main + src[b:]

# 3) swap the modal region (create + members + forward + delete + msg-menu)
a = src.find('<!-- New Conversation Modal -->')
b = src.find('<!-- Farmland mosaic generator -->')
if a < 0 or b < 0 or b < a:
    fail('modal markers not found')
src = src[:a] + modals + src[b:]

# 4) replace the main chat <script> (robust to any middle drift)
marker = '// [All chat functionality preserved]'
mi = src.find(marker)
if mi < 0:
    fail('main-script marker not found')
s = src.rfind('<script>', 0, mi)
e = src.find('</script>', mi)
if s < 0 or e < 0:
    fail('main-script bounds not found')
e += len('</script>')
src = src[:s] + '<script>\n' + js + '\n    </script>' + src[e:]

with open(PATH, 'w', encoding='utf-8') as f:
    f.write(src)
print('   OK chats.html upgraded')
ASM_EOF

echo ">> Applying UI upgrade..."
cp "$TMP"/new_extra.css "$TMP"/new_main.html "$TMP"/new_modals.html "$TMP"/new_chat.js "$TMP"/assemble_chats.py .
python3 assemble_chats.py; RC=$?
rm -f new_extra.css new_main.html new_modals.html new_chat.js assemble_chats.py
rm -rf "$TMP"
if [ $RC -ne 0 ]; then echo "X  Assembly failed; restore with: cp -a ${BK}/templates/chats.html templates/chats.html"; exit 1; fi

if command -v node >/dev/null 2>&1; then
  python3 - << 'CHKEOF'
import re
s=open('templates/chats.html',encoding='utf-8').read()
m=re.search(r'<script>\n(/\* ===== Agricore Chats.*?)\n    </script>', s, re.S)
open('.jscheck.js','w').write(m.group(1) if m else 'throw new Error("no match")')
CHKEOF
  node --check .jscheck.js && echo ">> Embedded JS syntax OK" || echo ">> WARNING: JS check failed"
  rm -f .jscheck.js
fi

echo ""
echo "============================================================"
echo "Chat UI upgraded on $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo n/a)."
echo "Review:    git diff -- templates/chats.html"
echo "Rollback:  cp -a ${BK}/templates/chats.html templates/chats.html"
echo "Now:       runserver, hard-refresh chats.html (Cmd-Shift-R), and click through."
echo "============================================================"
