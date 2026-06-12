// dale_ai.js: Global logic for Dale AI FAB and dialog

document.addEventListener('DOMContentLoaded', function () {
  const fab = document.getElementById('dale-ai-fab');
  const dialog = document.getElementById('dale-ai-dialog');
  const closeBtn = document.getElementById('dale-ai-close');
  const form = document.getElementById('dale-ai-form');
  const input = document.getElementById('dale-ai-input');
  const messages = document.getElementById('dale-ai-messages');
  const loader = document.getElementById('dale-ai-loader');

  if (!fab || !dialog) return;

  fab.addEventListener('click', () => {
    dialog.classList.remove('hidden');
    input.focus();
  });
  closeBtn.addEventListener('click', () => {
    dialog.classList.add('hidden');
  });
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    addMessage(text, 'user');
    input.value = '';
    // Show 'thinking' message instead of spinner
    let thinkingDiv = document.createElement('div');
    thinkingDiv.className = 'dale-ai-message dale-ai-message-bot dale-ai-thinking';
    thinkingDiv.textContent = 'Dale AI is thinking…';
    messages.appendChild(thinkingDiv);
    messages.scrollTop = messages.scrollHeight;
    try {
      // Try to send Authorization header if token is available
      const token = localStorage.getItem('access_token') || localStorage.getItem('token');
      const headers = {
        'Content-Type': 'application/json',
        'X-CSRFToken': getCookie('csrftoken'),
      };
      if (token) headers['Authorization'] = `Bearer ${token}`;

      // Build context for Multi-Farm page
      let context = {};
      if (window.userFarmsContext) context.farms = window.userFarmsContext;
      if (window.daleUserName) context.user_name = window.daleUserName;
      if (window.location.pathname.includes('multi_farm')) context.page = 'multi_farm';
      // Optionally, add more context as needed

      const body = { prompt: text };
      if (Object.keys(context).length > 0) body.context = context;

      const response = await fetch('/api/ai/dale/ask/', {
        method: 'POST',
        headers,
        body: JSON.stringify(body),
      });
      const data = await response.json();
      // Remove 'thinking' message
      const thinking = messages.querySelector('.dale-ai-thinking');
      if (thinking) thinking.remove();
      addMessage(data.reply || 'Sorry, I did not understand.', 'bot');
      // Highlight features if Dale AI gives highlight instructions
      handleHighlightInstruction(data.reply);
      // Handle actionable instructions from Dale AI
      if (data.action) {
        handleDaleAIAction(data.action);
      }
      // Parse Dale AI reply for highlight instructions and highlight elements
      function handleHighlightInstruction(reply) {
        if (!reply || typeof reply !== 'string') return;
        // Example: "Highlight the Add New Farm button" or "Focus on the professional card"
        const highlightRegex = /Highlight the ([\w\s-]+) button|Focus on the ([\w\s-]+) card|Highlight the ([\w\s-]+) filter|Highlight the ([\w\s-]+) input/i;
        const match = reply.match(highlightRegex);
        if (match) {
          let target = match[1] || match[2] || match[3] || match[4];
          if (!target) return;
          target = target.trim().toLowerCase().replace(/\s+/g, '-');
          // Try to find by id, class, or data attribute
          let el = document.getElementById(target) || document.querySelector(`.${target}`) || document.querySelector(`[data-highlight="${target}"]`);
          if (el) {
            el.classList.add('daleai-highlight');
            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
            setTimeout(() => el.classList.remove('daleai-highlight'), 2200);
          }
        }
      }
    } catch (err) {
      // Remove 'thinking' message
      const thinking = messages.querySelector('.dale-ai-thinking');
      if (thinking) thinking.remove();
      addMessage('Error: Could not reach Dale AI.', 'bot');
    } finally {
      // No spinner to hide anymore
    }
  });

  // Handle actionable instructions from Dale AI backend
  function handleDaleAIAction(action) {
    if (action.type === 'filter_products' && Array.isArray(action.product_ids)) {
      highlightProducts(action.product_ids);
    } else if (action.type === 'show_cart') {
      const cartDrawer = document.getElementById('cart-drawer');
      if (cartDrawer) cartDrawer.classList.remove('translate-x-full');
    } else if (action.type === 'navigate' && action.target) {
      window.location.href = action.target;
    } else if (action.type === 'show_message' && action.message) {
      addMessage(action.message, 'bot');
    }
    // Add more action types as needed
  }

  // Highlight or filter products in the grid
  function highlightProducts(productIds) {
    const grid = document.getElementById('product-grid-all');
    if (!grid) return;
    const cards = grid.querySelectorAll('[data-product-id]');
    cards.forEach(card => {
      if (productIds.includes(parseInt(card.dataset.productId))) {
        card.classList.add('ring-4', 'ring-emerald-400');
        card.scrollIntoView({ behavior: 'smooth', block: 'center' });
      } else {
        card.classList.remove('ring-4', 'ring-emerald-400');
      }
    });
  }
  function addMessage(text, who) {
    const div = document.createElement('div');
    div.className = 'dale-ai-message dale-ai-message-' + (who === 'user' ? 'user' : 'bot');
    div.textContent = text;
    messages.appendChild(div);
    messages.scrollTop = messages.scrollHeight;
  }
  function getCookie(name) {
    let cookieValue = null;
    if (document.cookie && document.cookie !== '') {
      const cookies = document.cookie.split(';');
      for (let i = 0; i < cookies.length; i++) {
        const cookie = cookies[i].trim();
        if (cookie.substring(0, name.length + 1) === (name + '=')) {
          cookieValue = decodeURIComponent(cookie.substring(name.length + 1));
          break;
        }
      }
    }
    return cookieValue;
  }
});
