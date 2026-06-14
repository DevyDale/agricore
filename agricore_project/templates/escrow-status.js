/*
 * Agricore — buyer escrow status widget (drop-in, no dependencies)
 * ---------------------------------------------------------------
 * Surfaces a buyer's escrow state for an order and lets them
 * pay into escrow and release funds on delivery — the same
 * /api/escrows/ endpoints the store dashboard uses.
 *
 * USAGE (add to your marketplace order / confirmation page):
 *
 *   <div data-agricore-escrow data-order-id="123"></div>
 *   <script src="escrow-status.js"></script>
 *
 * Optional attributes on the container:
 *   data-api="/api"     (API base, default "/api")
 *   data-token-key="access_token"   (localStorage key for the JWT)
 *
 * It auto-initialises every [data-agricore-escrow] on the page.
 * Re-render any time with: window.AgricoreEscrow.refreshAll()
 */
(function () {
  "use strict";

  var STYLE_ID = "agc-escrow-style";
  function injectStyle() {
    if (document.getElementById(STYLE_ID)) return;
    var css =
      ".agc-esc{font-family:Inter,system-ui,sans-serif;border:1px solid #ece4d6;border-radius:16px;padding:16px;background:#fff;max-width:520px}" +
      ".agc-esc__row{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}" +
      ".agc-esc__title{font-weight:700;color:#16271c;margin:0}" +
      ".agc-esc__sub{font-size:12px;color:#6b7280;margin:2px 0 0}" +
      ".agc-esc__pill{font-size:12px;font-weight:600;padding:3px 10px;border-radius:9999px}" +
      ".agc-esc__pill--pending{background:#fef3c7;color:#92400e}" +
      ".agc-esc__pill--held{background:#dbeafe;color:#1d4ed8}" +
      ".agc-esc__pill--released{background:#d1fae5;color:#047857}" +
      ".agc-esc__pill--refunded{background:#f3f4f6;color:#6b7280}" +
      ".agc-esc__pill--disputed{background:#fee2e2;color:#dc2626}" +
      ".agc-esc__btn{cursor:pointer;border:0;border-radius:10px;padding:9px 16px;font-size:13px;font-weight:600;display:inline-flex;align-items:center;gap:6px;margin-top:12px;color:#fff;background:linear-gradient(135deg,#10b981,#047857)}" +
      ".agc-esc__btn:disabled{opacity:.6;cursor:default}" +
      ".agc-esc__btn--ghost{background:#fff;color:#047857;border:1px solid #a4d6ba}" +
      ".agc-esc__note{font-size:12px;color:#6b7280;margin-top:10px;display:flex;gap:6px;align-items:flex-start}" +
      ".agc-esc__lock{color:#047857}";
    var s = document.createElement("style");
    s.id = STYLE_ID;
    s.textContent = css;
    document.head.appendChild(s);
  }

  var SYM = { NGN: "\u20a6", USD: "$", UGX: "USh ", KES: "KSh ", GHS: "GH\u20b5", ZAR: "R", TZS: "TSh ", RWF: "FRw " };
  function money(amount, cur) {
    var c = String(cur || "").toUpperCase();
    var sym = SYM[c] || (c ? c + " " : "");
    return sym + Number(amount || 0).toLocaleString(undefined, { maximumFractionDigits: 2 });
  }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function listFrom(d) { return Array.isArray(d) ? d : (d && d.results ? d.results : []); }
  function orderIdOf(e) { var o = e.order; return Number(o && (o.id != null ? o.id : o)); }

  function cfg(el) {
    return {
      api: el.getAttribute("data-api") || "/api",
      tokenKey: el.getAttribute("data-token-key") || "access_token",
      orderId: Number(el.getAttribute("data-order-id"))
    };
  }
  function authHeaders(el, json) {
    var t = localStorage.getItem(cfg(el).tokenKey) || "";
    var h = { Authorization: "Bearer " + t };
    if (json) h["Content-Type"] = "application/json";
    return h;
  }

  function setBusy(el, busy) {
    var btns = el.querySelectorAll(".agc-esc__btn");
    for (var i = 0; i < btns.length; i++) btns[i].disabled = !!busy;
  }

  function render(el, escrow, opts) {
    opts = opts || {};
    var c = cfg(el);
    var inner = '<div class="agc-esc">';
    if (!escrow) {
      inner +=
        '<div class="agc-esc__row"><div><p class="agc-esc__title">Secure escrow</p>' +
        '<p class="agc-esc__sub">Pay safely \u2014 funds are held until you confirm delivery.</p></div></div>' +
        '<button class="agc-esc__btn" data-act="paynew">Pay with escrow</button>' +
        '<p class="agc-esc__note"><span class="agc-esc__lock">\u{1f512}</span> Card details are entered on Flutterwave\u2019s encrypted page.</p>';
    } else {
      var st = String(escrow.status || "").toLowerCase();
      var label = st ? st.charAt(0).toUpperCase() + st.slice(1) : "Unknown";
      inner +=
        '<div class="agc-esc__row"><div><p class="agc-esc__title">Escrow \u2022 ' + money(escrow.amount, escrow.currency) + '</p>' +
        '<p class="agc-esc__sub">Order #' + esc(orderIdOf(escrow)) + '</p></div>' +
        '<span class="agc-esc__pill agc-esc__pill--' + esc(st) + '">' + esc(label) + '</span></div>';
      if (st === "pending") {
        inner += '<button class="agc-esc__btn" data-act="pay" data-id="' + escrow.id + '">Pay now</button>';
      } else if (st === "held") {
        inner += '<button class="agc-esc__btn" data-act="release" data-id="' + escrow.id + '">Confirm delivery &amp; release</button>' +
          '<p class="agc-esc__note">Only release once you\u2019ve received your order \u2014 this pays the seller.</p>';
      } else if (st === "released") {
        inner += '<p class="agc-esc__note"><span class="agc-esc__lock">\u2714</span> Completed \u2014 funds released to the seller.</p>';
      }
      if (opts.waiting) {
        inner += '<p class="agc-esc__note">Finishing payment? <button class="agc-esc__btn agc-esc__btn--ghost" data-act="refresh">Refresh status</button></p>';
      }
    }
    inner += "</div>";
    el.innerHTML = inner;
    el.querySelectorAll("[data-act]").forEach(function (b) {
      b.addEventListener("click", function () { onAction(el, b.getAttribute("data-act"), b.getAttribute("data-id")); });
    });
  }

  async function findEscrow(el) {
    var c = cfg(el);
    try {
      var r = await fetch(c.api + "/escrows/", { headers: authHeaders(el) });
      if (!r.ok) return null;
      var list = listFrom(await r.json());
      return list.filter(function (e) { return orderIdOf(e) === c.orderId; })[0] || null;
    } catch (e) { return null; }
  }

  async function fetchOrder(el) {
    var c = cfg(el);
    try {
      var r = await fetch(c.api + "/orders/" + c.orderId + "/", { headers: authHeaders(el) });
      if (!r.ok) return null;
      return await r.json();
    } catch (e) { return null; }
  }

  async function startPayment(el, escrowId) {
    var c = cfg(el);
    setBusy(el, true);
    try {
      var r = await fetch(c.api + "/escrows/" + escrowId + "/pay/", { method: "POST", headers: authHeaders(el) });
      var data = await r.json().catch(function () { return {}; });
      if (!r.ok) throw new Error(data.detail || "Could not start payment.");
      if (data.checkout_link) {
        window.open(data.checkout_link, "_blank");
        var e = await findEscrow(el);
        render(el, e, { waiting: true });
      } else { throw new Error("No checkout link returned."); }
    } catch (err) {
      alert(err.message || "Payment could not start.");
      setBusy(el, false);
    }
  }

  async function onAction(el, act, id) {
    var c = cfg(el);
    if (act === "refresh") { return load(el); }
    if (act === "paynew") {
      setBusy(el, true);
      var order = await fetchOrder(el);
      if (!order) { alert("Could not load the order."); setBusy(el, false); return; }
      try {
        var r = await fetch(c.api + "/escrows/", {
          method: "POST", headers: authHeaders(el, true),
          body: JSON.stringify({ order: c.orderId, amount: Number(order.total_amount || 0) || 0, currency: order.currency || "UGX" })
        });
        var created = await r.json().catch(function () { return {}; });
        if (!r.ok) throw new Error(created.detail || (created && Object.values(created)[0]) || "Could not start escrow.");
        await startPayment(el, created.id);
      } catch (err) { alert(err.message || "Could not start escrow."); setBusy(el, false); }
      return;
    }
    if (act === "pay") { return startPayment(el, id); }
    if (act === "release") {
      if (!window.confirm("Confirm you received this order? This releases the held funds to the seller and cannot be undone.")) return;
      setBusy(el, true);
      try {
        var rr = await fetch(c.api + "/escrows/" + id + "/release/", { method: "POST", headers: authHeaders(el) });
        var d = await rr.json().catch(function () { return {}; });
        if (!rr.ok) throw new Error(d.detail || "Could not release funds.");
        load(el);
      } catch (err) { alert(err.message || "Could not release funds."); setBusy(el, false); }
    }
  }

  async function load(el) {
    if (!cfg(el).orderId) { el.innerHTML = ""; return; }
    var escrow = await findEscrow(el);
    render(el, escrow);
  }

  function init() {
    injectStyle();
    document.querySelectorAll("[data-agricore-escrow]").forEach(function (el) {
      if (el.getAttribute("data-agc-init")) return;
      el.setAttribute("data-agc-init", "1");
      load(el);
    });
  }

  window.AgricoreEscrow = {
    init: init,
    refreshAll: function () { document.querySelectorAll("[data-agricore-escrow]").forEach(load); }
  };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
