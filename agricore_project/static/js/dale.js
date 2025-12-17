// Dale AI frontend helper
(function(){
  const API = '/api/ai/dale/ask/';

  async function askDale(prompt, context={}, history=[]) {
    const token = localStorage.getItem('access_token') || localStorage.getItem('token');
    if (!token) {
      throw new Error('Not authenticated');
    }
    const res = await fetch(API, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
        'X-Page-Context': context.page || ''
      },
      body: JSON.stringify({ prompt, context, history })
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.detail || 'AI request failed');
    }
    return res.json();
  }

  function attachFab() {
    if (document.getElementById('dale-ai-btn')) return; // already exists
    const btn = document.createElement('button');
    btn.id = 'dale-ai-btn';
    btn.className = 'fixed bottom-6 right-6 bg-gradient-to-r from-emerald-600 to-teal-600 text-white rounded-full w-14 h-14 shadow-2xl flex items-center justify-center text-2xl z-50';
    btn.innerHTML = '<i class="fas fa-robot"></i>';
    btn.title = 'Dale AI Assistant';
    document.body.appendChild(btn);

    btn.addEventListener('click', openModal);
  }

  function ensureModal() {
    let modal = document.getElementById('dale-ai-modal');
    if (modal) return modal;
    modal = document.createElement('div');
    modal.id = 'dale-ai-modal';
    modal.className = 'fixed inset-0 bg-black/70 hidden items-center justify-center z-50';
    modal.innerHTML = `
      <div class="glass rounded-3xl shadow-2xl p-6 max-w-2xl w-full mx-6 bg-white">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-2xl font-bold text-emerald-700 flex items-center gap-3"><i class="fas fa-robot"></i> Dale AI Assistant</h2>
          <button id="dale-ai-close" class="text-gray-600 hover:text-gray-900"><i class="fas fa-times"></i></button>
        </div>
        <div id="dale-ai-suggestions" class="flex flex-wrap gap-2 mb-3"></div>
        <div id="dale-ai-log" class="space-y-3 max-h-[50vh] overflow-y-auto mb-4"></div>
        <div class="flex gap-2">
          <input id="dale-ai-input" class="flex-1 border border-emerald-300 rounded-xl px-3 py-2 focus:outline-none" placeholder="Ask Dale..." />
          <button id="dale-ai-send" class="px-4 py-2 bg-gradient-to-r from-emerald-600 to-teal-600 text-white rounded-xl">Send</button>
        </div>
      </div>`;
    document.body.appendChild(modal);
    document.getElementById('dale-ai-close').addEventListener('click', () => modal.classList.add('hidden'));
    document.getElementById('dale-ai-send').addEventListener('click', sendFromModal);
    return modal;
  }

  function openModal(){
    const m = ensureModal();
    renderSuggestions();
    m.classList.remove('hidden');
  }

  async function sendFromModal(){
    const input = document.getElementById('dale-ai-input');
    const text = (input.value || '').trim();
    if (!text) return;
    const log = document.getElementById('dale-ai-log');
    const page = (document.title || '').toLowerCase();
    appendLog(log, text, true);
    input.value='';
    try {
      const context = buildContextForPage();
      const res = await askDale(text, context);
      appendLog(log, res.reply, false);
    } catch (e) {
      appendLog(log, `Error: ${e.message}`, false);
    }
  }

  function appendLog(container, text, mine){
    const row = document.createElement('div');
    row.className = 'flex ' + (mine ? 'justify-end' : 'justify-start');
    row.innerHTML = `<div class="px-3 py-2 rounded-xl ${mine ? 'bg-emerald-600 text-white' : 'bg-emerald-50'} max-w-[80%]">${escapeHtml(text)}</div>`;
    container.appendChild(row);
    container.scrollTop = container.scrollHeight;
  }

  function escapeHtml(str){
    return String(str).replace(/[&<>"]+/g, s => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[s]));
  }

  function buildContextForPage(){
    const path = location.pathname;
    const page = path.split('/').pop();
    const extras = {};
    // Example hooks per page
    if (page.includes('workforce')) {
      // collect ratings/reviews visible in DOM if any
      extras.section = 'workforce';
    } else if (page.includes('marketplace')) {
      extras.section = 'marketplace';
    } else if (page.includes('digital_store')) {
      extras.section = 'digital_store';
    } else if (page.includes('chats')) {
      extras.section = 'chats';
    } else {
      extras.section = 'generic';
    }
    return { page, type: 'page', id: null, extras };
  }

  function getSuggestionsForPage(){
    const ctx = buildContextForPage();
    const section = ctx.extras.section;
    const common = [
      'Summarize what I was last doing and propose the next best step.',
      'Draft a concise to-do list for this page.',
    ];
    if (section === 'marketplace') {
      return [
        'Recommend top 3 products to promote based on ratings/reviews.',
        'Which store has the best reputation and why?',
        'Suggest pricing or discount tweaks to lift conversion.',
        ...common,
      ];
    }
    if (section === 'workforce') {
      return [
        'Recommend top 3 professionals to contact with reasons.',
        'Suggest a hiring outreach message for the best-fit pro.',
        ...common,
      ];
    }
    if (section === 'digital_store') {
      return [
        'Review my store metrics and suggest two quick wins to increase sales.',
        'Pick one product to feature on the homepage and explain why.',
        'Suggest ad copy and CTA for a new promotion.',
        ...common,
      ];
    }
    if (section === 'chats') {
      return [
        'Generate a friendly, concise reply to the latest customer message.',
        'Summarize the current conversation and propose next actions.',
        ...common,
      ];
    }
    return common;
  }

  function renderSuggestions(){
    const box = document.getElementById('dale-ai-suggestions');
    if (!box) return;
    box.innerHTML = '';
    const list = getSuggestionsForPage();
    list.forEach(text => {
      const btn = document.createElement('button');
      btn.className = 'px-3 py-2 bg-emerald-50 text-emerald-700 rounded-xl text-sm hover:bg-emerald-100 border border-emerald-100';
      btn.textContent = text;
      btn.addEventListener('click', async () => {
        const log = document.getElementById('dale-ai-log');
        appendLog(log, text, true);
        try {
          const res = await askDale(text, buildContextForPage());
          appendLog(log, res.reply, false);
        } catch (e) {
          appendLog(log, `Error: ${e.message}`, false);
        }
      });
      box.appendChild(btn);
    });
  }

  // Auto attach FAB
  document.addEventListener('DOMContentLoaded', () => {
    attachFab();
  });

  // expose globally
  window.DaleAI = { ask: askDale };
})();
