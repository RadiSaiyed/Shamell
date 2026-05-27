/* Shamell Hotels mini-app — single-page client.
   Generic hotels module. Registered partners: VENEZIA Hotel (Venice),
   Al Faisaliah (Riyadh). Locale is driven by the host through
   `window.__shamellSetLocale(...)` (see i18n.js) — default 'de'.
*/

'use strict';

const STORAGE_KEY = 'shamell.hotels.state.v1';
const $ = (id) => document.getElementById(id);
const app = $('app');
const toastEl = $('toast');
const tabbar = $('tabbar');
const navBack = $('navBack');
const navTitle = $('navTitle');
const navMore = $('navMore');

const state = {
  hotels: [],
  selectedHotel: null,
  tab: 'info',
  search: { checkIn: today(+1), checkOut: today(+3), guests: 2, roomType: 'any' },
  cart: {},
  chat: [],
  history: [],
};

const t = (key) => window.__shamellI18n.t(key);
const isRTL = () => window.__shamellI18n.isRTL();
const lc = () => window.__shamellI18n.locale();

// Fields in `hotels.json` can be plain strings or `{ de, en, ar }`
// objects. Pick the active locale, falling back to German, then any.
function pickLang(v) {
  if (v == null) return '';
  if (typeof v === 'string') return v;
  if (typeof v === 'object') {
    return v[lc()] || v.de || v.en || Object.values(v)[0] || '';
  }
  return String(v);
}

restoreState();

// ---------- Boot ----------
loadHotels()
  .then((data) => {
    state.hotels = data.hotels || [];
    renderDirectory();
  })
  .catch((err) => {
    app.innerHTML = `<div class="empty"><h3>${escapeHtml(t('lostConnection'))}</h3><p>${escapeHtml(String(err))}</p></div>`;
  });

async function loadHotels() {
  // hotels-data.js (loaded before app.js) sets window.SHAMELL_HOTELS_DATA.
  // We used to fetch('hotels.json'), but Android WebView blocks fetch() of
  // file:// resources unless allowFileAccessFromFileURLs is explicitly
  // turned on — and that setting is deprecated in webview_flutter. Using
  // a plain <script> tag works under file:// without any extra config.
  if (window.SHAMELL_HOTELS_DATA) return window.SHAMELL_HOTELS_DATA;
  // Defensive fallback in case the bundle is ever served from http(s)
  // (web preview, future PWA host) where fetch() works.
  const res = await fetch('hotels.json', { cache: 'no-cache' });
  if (!res.ok) throw new Error('hotels.json HTTP ' + res.status);
  return res.json();
}

// ---------- Navigation ----------
navBack.addEventListener('click', () => goBack());
navMore.addEventListener('click', () => shareCurrent());

function goBack() {
  if (state.history.length <= 1) return;
  state.history.pop();
  const prev = state.history[state.history.length - 1];
  if (prev === 'directory') {
    state.selectedHotel = null;
    state.history = ['directory'];
    renderDirectory();
  } else if (prev && prev.startsWith('hotel:')) {
    state.tab = prev.split(':')[2] || 'info';
    renderHotel();
  }
  navBack.hidden = state.history.length <= 1;
}

// Re-render current view when the host swaps locale.
window.__shamellOnLocaleChange = function () {
  if (!state.history.length) return;
  const top = state.history[state.history.length - 1];
  if (top === 'directory') renderDirectory();
  else if (top && top.startsWith('hotel:')) renderHotel();
  // Confirm/booked screens are transient — leave as-is.
};

// ---------- Directory ----------
function renderDirectory() {
  setTitle(t('navTitle'));
  tabbar.hidden = true;
  state.history = ['directory'];
  navBack.hidden = true;
  app.innerHTML = `
    <section class="screen">
      <div class="directory__hero">
        <h1>${escapeHtml(t('dirHeadline'))}</h1>
        <p>${escapeHtml(t('dirSubline'))}</p>
      </div>
      <div class="section-title">${escapeHtml(t('sectionRecommended'))}</div>
      ${state.hotels.map(hotelCard).join('')}
    </section>
  `;
  app.querySelectorAll('[data-hotel]').forEach((el) => {
    el.addEventListener('click', () => openHotel(el.dataset.hotel));
  });
}

function hotelCard(h) {
  const name = pickLang(h.name);
  const tagline = pickLang(h.tagline);
  const city = pickLang(h.city);
  return `
    <article class="hotel-card" data-hotel="${h.id}">
      <img class="hotel-card__img" src="${escapeAttr(h.hero)}" alt="${escapeAttr(name)}" loading="lazy" onerror="this.style.background='#0e3a53';this.removeAttribute('src')" />
      <div class="hotel-card__body">
        <h3 class="hotel-card__name">${escapeHtml(name)}</h3>
        <p class="hotel-card__tag">${escapeHtml(tagline)} · ${escapeHtml(city)}</p>
        <div class="hotel-card__row">
          <span class="rating">★ ${h.rating.toFixed(1)} <span class="rating__count">(${h.reviewCount})</span></span>
          <span class="price">${escapeHtml(t('from'))} ${formatPrice(h.priceFrom, h.currency)} <small>${escapeHtml(t('perNight'))}</small></span>
        </div>
      </div>
    </article>
  `;
}

// ---------- Hotel detail ----------
function openHotel(id) {
  const h = state.hotels.find((x) => x.id === id);
  if (!h) return;
  state.selectedHotel = h;
  state.tab = 'info';
  state.history = ['directory', `hotel:${h.id}:info`];
  navBack.hidden = false;
  renderHotel();
}

function renderHotel() {
  const h = state.selectedHotel;
  if (!h) return renderDirectory();
  setTitle(pickLang(h.name));
  tabbar.hidden = false;
  updateTabbar();

  if (state.tab === 'info') renderInfo(h);
  else if (state.tab === 'rooms') renderRooms(h);
  else if (state.tab === 'menu') renderMenu(h);
  else if (state.tab === 'concierge') renderConcierge(h);

  state.history[state.history.length - 1] = `hotel:${h.id}:${state.tab}`;
  persistState();
}

function updateTabbar() {
  // Tab labels follow the active locale.
  const labels = { info: t('tabInfo'), rooms: t('tabRooms'), menu: t('tabMenu'), concierge: t('tabConcierge') };
  tabbar.querySelectorAll('.tab').forEach((tab) => {
    tab.classList.toggle('tab--active', tab.dataset.tab === state.tab);
    const label = tab.querySelector('span');
    if (label && labels[tab.dataset.tab] !== undefined) label.textContent = labels[tab.dataset.tab];
  });
}
tabbar.querySelectorAll('.tab').forEach((tab) => {
  tab.addEventListener('click', () => {
    state.tab = tab.dataset.tab;
    renderHotel();
  });
});

// ---------- Info tab ----------
function renderInfo(h) {
  app.innerHTML = `
    <section class="screen">
      <div class="info__hero">
        <img src="${escapeAttr(h.hero)}" alt="" />
        <h1>${escapeHtml(pickLang(h.name))}</h1>
      </div>
      <div class="meta-row">
        <span class="rating">★ ${h.rating.toFixed(1)} <span class="rating__count">(${h.reviewCount})</span></span>
        <span>·</span>
        <span>${escapeHtml(pickLang(h.city))}, ${escapeHtml(pickLang(h.country))}</span>
      </div>

      <div class="section-title">${escapeHtml(t('sectionAmenities'))}</div>
      <div class="amenities">
        ${h.amenities.map(amenityCell).join('')}
      </div>

      <div class="section-title">${escapeHtml(t('sectionAbout'))}</div>
      <div class="about-card">
        <p style="margin:0">${escapeHtml(pickLang(h.description))}</p>
        <div class="contact">
          <div><strong>${escapeHtml(t('labelAddress'))}:</strong> ${escapeHtml(pickLang(h.address))}</div>
          <div><strong>${escapeHtml(t('labelPhone'))}:</strong> ${escapeHtml(h.phone)}</div>
          <div><strong>${escapeHtml(t('labelEmail'))}:</strong> ${escapeHtml(h.email)}</div>
        </div>
      </div>

      <div class="section-title">${escapeHtml(t('sectionGallery'))}</div>
      <div class="gallery">
        ${h.gallery.map((src) => `<img src="${escapeAttr(src)}" alt="" loading="lazy" />`).join('')}
      </div>

      <div style="margin-top:18px">
        <button class="btn btn--block" data-action="bookNow">${escapeHtml(t('bookNow'))}</button>
      </div>
    </section>
  `;
  app.querySelector('[data-action=bookNow]').addEventListener('click', () => {
    state.tab = 'rooms';
    renderHotel();
  });
}

function amenityCell(a) {
  const map = {
    wifi: '📶', pool: '🏊', restaurant: '🍝',
    parking: '🅿️', concierge: '🛎️', gym: '🏋️',
    desert: '🏜️', mosque: '🕌', falconry: '🦅',
  };
  const icon = map[a.icon] || '✨';
  return `<div class="amenity"><span class="amenity__icon">${icon}</span><span>${escapeHtml(pickLang(a.label))}</span></div>`;
}

// ---------- Rooms tab ----------
function renderRooms(h) {
  const s = state.search;
  app.innerHTML = `
    <section class="screen">
      <div class="search-card">
        <div><label>${escapeHtml(t('checkIn'))}</label><input type="date" id="ci" value="${s.checkIn}" /></div>
        <div><label>${escapeHtml(t('checkOut'))}</label><input type="date" id="co" value="${s.checkOut}" /></div>
        <div><label>${escapeHtml(t('guestsLabel'))}</label>
          <select id="g">
            ${[1,2,3,4].map((n) => `<option value="${n}" ${n===s.guests?'selected':''}>${n} ${n===1?escapeHtml(t('guestSingular')):escapeHtml(t('guestPlural'))}</option>`).join('')}
          </select>
        </div>
        <div><label>${escapeHtml(t('roomType'))}</label>
          <select id="rt">
            <option value="any" ${s.roomType==='any'?'selected':''}>${escapeHtml(t('allRoomTypes'))}</option>
            ${h.rooms.map((r) => `<option value="${r.id}" ${s.roomType===r.id?'selected':''}>${escapeHtml(pickLang(r.name))}</option>`).join('')}
          </select>
        </div>
      </div>

      <div class="section-title">${escapeHtml(t('sectionAvailable'))}</div>
      <div id="roomList">${h.rooms.filter((r) => s.roomType==='any' || r.id===s.roomType).map((r) => roomCard(r, s, h)).join('')}</div>
    </section>
  `;

  const refresh = () => {
    state.search.checkIn = $('ci').value;
    state.search.checkOut = $('co').value;
    state.search.guests = parseInt($('g').value, 10);
    state.search.roomType = $('rt').value;
    persistState();
    renderRooms(h);
  };
  ['ci','co','g','rt'].forEach((id) => $(id).addEventListener('change', refresh));

  app.querySelectorAll('[data-book]').forEach((b) => {
    b.addEventListener('click', () => bookRoom(h, b.dataset.book));
  });
}

function roomCard(r, s, h) {
  const nights = Math.max(1, nightsBetween(s.checkIn, s.checkOut));
  const subtotal = r.price * nights;
  const cur = h.currency || 'EUR';
  return `
    <div class="room-card">
      <img src="${escapeAttr(r.image)}" alt="" loading="lazy" />
      <div class="room-card__body">
        <h4 class="room-card__name">${escapeHtml(pickLang(r.name))}</h4>
        <p class="room-card__desc">${escapeHtml(pickLang(r.description))}</p>
        <div class="room-card__feat">
          ${(r.features || []).map((f) => `<span class="feat-chip">${escapeHtml(pickLang(f))}</span>`).join('')}
        </div>
        <div class="room-card__foot">
          <span class="price">${formatPrice(subtotal, cur)} <small>· ${nights} ${nights===1?escapeHtml(t('nightOne')):escapeHtml(t('nightMany'))}</small></span>
          <button class="btn" data-book="${r.id}">${escapeHtml(t('book'))}</button>
        </div>
      </div>
    </div>
  `;
}

function bookRoom(h, roomId) {
  const room = h.rooms.find((r) => r.id === roomId);
  if (!room) return;
  const s = state.search;
  const nights = Math.max(1, nightsBetween(s.checkIn, s.checkOut));
  const cur = h.currency || 'EUR';
  const total = room.price * nights;
  if (s.guests > room.maxGuests) {
    showToast(t('tooManyGuests')(room.maxGuests));
    return;
  }
  tabbar.hidden = true;
  state.history.push('confirm:booking');
  navBack.hidden = false;
  setTitle(t('bookingConfirmTitle'));
  app.innerHTML = `
    <section class="screen">
      <div class="confirm">
        <h2>${escapeHtml(t('almostDone'))}</h2>
        <p style="color:#6b7280;font-size:13px;margin:0 0 12px">${escapeHtml(t('reviewPlease'))}</p>
        <dl>
          <dt>${escapeHtml(t('lblHotel'))}</dt><dd>${escapeHtml(pickLang(h.name))}</dd>
          <dt>${escapeHtml(t('lblRoom'))}</dt><dd>${escapeHtml(pickLang(room.name))}</dd>
          <dt>${escapeHtml(t('checkIn'))}</dt><dd>${formatDate(s.checkIn)}</dd>
          <dt>${escapeHtml(t('checkOut'))}</dt><dd>${formatDate(s.checkOut)}</dd>
          <dt>${escapeHtml(t('lblNights'))}</dt><dd>${nights}</dd>
          <dt>${escapeHtml(t('lblGuests'))}</dt><dd>${s.guests}</dd>
        </dl>
        <div class="confirm__total">${formatPrice(total, cur)}</div>
      </div>
      <div style="margin-top:14px;display:grid;grid-template-columns:1fr 1fr;gap:8px">
        <button class="btn btn--ghost" data-cancel>${escapeHtml(t('cancel'))}</button>
        <button class="btn btn--gold" data-pay>${escapeHtml(t('payWithShamell'))}</button>
      </div>
    </section>
  `;
  app.querySelector('[data-cancel]').addEventListener('click', () => { goBack(); renderHotel(); });
  app.querySelector('[data-pay]').addEventListener('click', () => completeBooking(h, room, total, cur));
}

function completeBooking(h, room, total, cur) {
  const ref = 'SHM-' + Math.random().toString(36).slice(2, 8).toUpperCase();
  hostBridge('createBooking', {
    hotelId: h.id, roomId: room.id,
    checkIn: state.search.checkIn, checkOut: state.search.checkOut,
    guests: state.search.guests, amount: total, currency: cur, ref,
  });
  // Phase 5 hand-off — the host's payments page reads memo+hotelId
  // and stamps them onto the /transfer body so payments_service can
  // fire the hotels webhook on commit. Without these two fields, the
  // booking just stays `pending` and the operator has to mark-paid
  // manually.
  hostBridge('openPayments', {
    amount: total,
    currency: cur,
    memo: ref,                // canonical: booking reference, not free text
    hotelId: h.id,            // tells payments which hotel to notify
    displayLabel: `${pickLang(h.name)} · ${pickLang(room.name)}`,
    ref,
  });
  setTitle(t('bookedTitle'));
  app.innerHTML = `
    <section class="screen">
      <div class="confirm" style="text-align:center">
        <div style="font-size:48px;line-height:1;margin-bottom:6px">✅</div>
        <h2 style="text-align:${isRTL()?'right':'left'}">${escapeHtml(t('bookedHeadline'))}</h2>
        <dl>
          <dt>${escapeHtml(t('lblReference'))}</dt><dd>${ref}</dd>
          <dt>${escapeHtml(t('lblHotel'))}</dt><dd>${escapeHtml(pickLang(h.name))}</dd>
          <dt>${escapeHtml(t('lblRoom'))}</dt><dd>${escapeHtml(pickLang(room.name))}</dd>
          <dt>${escapeHtml(t('lblAmount'))}</dt><dd>${formatPrice(total, cur)}</dd>
        </dl>
        <p style="color:#6b7280;font-size:12.5px;margin-top:12px">${escapeHtml(t('bookedNote'))}</p>
      </div>
      <div style="margin-top:14px">
        <button class="btn btn--block" data-done>${escapeHtml(t('done'))}</button>
      </div>
    </section>
  `;
  app.querySelector('[data-done]').addEventListener('click', () => {
    state.history = ['directory', `hotel:${h.id}:info`];
    state.tab = 'info';
    renderHotel();
  });
}

// ---------- Menu tab ----------
function renderMenu(h) {
  app.innerHTML = `
    <section class="screen">
      <div class="section-title">${escapeHtml(t('sectionRoomService'))}</div>
      ${h.menu.map(menuSection).join('')}
      <div style="height:90px"></div>
    </section>
  `;
  app.querySelectorAll('[data-add]').forEach((b) => b.addEventListener('click', () => bumpCart(b.dataset.add, +1)));
  app.querySelectorAll('[data-sub]').forEach((b) => b.addEventListener('click', () => bumpCart(b.dataset.sub, -1)));
  renderCartBar(h);
}

function menuSection(sec) {
  return `
    <div class="menu-section">
      <h4 class="menu-section__title">${escapeHtml(pickLang(sec.section))}</h4>
      ${sec.items.map(menuItem).join('')}
    </div>
  `;
}

function menuItem(it) {
  const qty = state.cart[it.id] || 0;
  return `
    <div class="menu-item">
      <div class="menu-item__body">
        <h5 class="menu-item__name">${escapeHtml(pickLang(it.name))}</h5>
        <p class="menu-item__desc">${escapeHtml(pickLang(it.desc))}</p>
      </div>
      <div class="menu-item__price">${formatCurrencySymbol(it.price, (state.selectedHotel && state.selectedHotel.currency) || 'EUR')}</div>
      ${qty === 0
        ? `<button class="btn" data-add="${it.id}">+</button>`
        : `<div class="qty">
             <button data-sub="${it.id}">−</button>
             <span>${qty}</span>
             <button data-add="${it.id}">+</button>
           </div>`}
    </div>
  `;
}

function bumpCart(id, delta) {
  const q = (state.cart[id] || 0) + delta;
  if (q <= 0) delete state.cart[id]; else state.cart[id] = q;
  persistState();
  renderMenu(state.selectedHotel);
}

function renderCartBar(h) {
  const items = flattenMenu(h);
  let count = 0, total = 0;
  for (const [id, q] of Object.entries(state.cart)) {
    const it = items.find((x) => x.id === id);
    if (!it) continue;
    count += q;
    total += q * it.price;
  }
  const old = document.querySelector('.cart-bar');
  if (old) old.remove();
  if (count === 0) return;
  const bar = document.createElement('div');
  bar.className = 'cart-bar';
  bar.innerHTML = `
    <div>
      <div class="cart-bar__total">${formatPrice(total, h.currency || 'EUR')}</div>
      <div class="cart-bar__count">${count} ${escapeHtml(t('lblItems'))}</div>
    </div>
    <button class="cart-bar__btn">${escapeHtml(t('orderBtn'))}</button>
  `;
  bar.querySelector('.cart-bar__btn').addEventListener('click', () => placeOrder(h, items, total, count));
  document.body.appendChild(bar);
}

function placeOrder(h, items, total, count) {
  const cur = h.currency || 'EUR';
  const ref = 'RS-' + Math.random().toString(36).slice(2, 7).toUpperCase();
  const orderItems = Object.entries(state.cart).map(([id, q]) => {
    const it = items.find((x) => x.id === id);
    return it ? { id, name: pickLang(it.name), qty: q, price: it.price } : null;
  }).filter(Boolean);
  hostBridge('createOrder', { hotelId: h.id, items: orderItems, amount: total, currency: cur, ref });
  // Same Phase-5 hand-off as booking-pay: memo = reference (RS-…)
  // so payments_service routes the auto-confirm webhook to
  // /v1/hotels/.../orders/by-ref/RS-…/payment.
  hostBridge('openPayments', {
    amount: total,
    currency: cur,
    memo: ref,
    hotelId: h.id,
    displayLabel: `${pickLang(h.name)} · Room-Service`,
    ref,
  });
  state.cart = {};
  persistState();
  setTitle(t('orderedTitle'));
  tabbar.hidden = true;
  document.querySelectorAll('.cart-bar').forEach((el) => el.remove());
  app.innerHTML = `
    <section class="screen">
      <div class="confirm" style="text-align:center">
        <div style="font-size:48px;line-height:1;margin-bottom:6px">🛎️</div>
        <h2 style="text-align:${isRTL()?'right':'left'}">${escapeHtml(t('orderedHeadline'))}</h2>
        <dl>
          <dt>${escapeHtml(t('lblReference'))}</dt><dd>${ref}</dd>
          <dt>${escapeHtml(t('lblHotel'))}</dt><dd>${escapeHtml(pickLang(h.name))}</dd>
          <dt>${escapeHtml(t('lblItems'))}</dt><dd>${count}</dd>
          <dt>${escapeHtml(t('lblAmount'))}</dt><dd>${formatPrice(total, cur)}</dd>
        </dl>
        <p style="color:#6b7280;font-size:12.5px;margin-top:12px">${escapeHtml(t('orderedNote'))}</p>
      </div>
      <div style="margin-top:14px">
        <button class="btn btn--block" data-done>${escapeHtml(t('backToHotel'))}</button>
      </div>
    </section>
  `;
  app.querySelector('[data-done]').addEventListener('click', () => {
    state.tab = 'info';
    renderHotel();
  });
}

function flattenMenu(h) { return h.menu.flatMap((s) => s.items); }

// ---------- Concierge tab ----------
function renderConcierge(h) {
  if (state.chat.length === 0) {
    state.chat.push({ role: 'bot', text: pickLang(h.concierge.greeting) });
  }
  app.innerHTML = `
    <section class="screen">
      <div class="handoff">
        <p><strong>${escapeHtml(pickLang(h.concierge.displayName))}</strong><br/>${escapeHtml(t('conciergeRespHours'))}: ${escapeHtml(h.concierge.responseHours)}</p>
        <button class="btn btn--ghost" data-handoff>${escapeHtml(t('conciergeOpenChat'))}</button>
      </div>

      <div class="chat" id="chat">
        ${state.chat.map(bubbleHtml).join('')}
        <div class="chat__input">
          <input id="chatIn" type="text" placeholder="${escapeAttr(t('conciergePlaceholder'))}" />
          <button id="chatSend">${escapeHtml(t('send'))}</button>
        </div>
      </div>
    </section>
  `;
  const send = () => {
    const txt = $('chatIn').value.trim();
    if (!txt) return;
    state.chat.push({ role: 'me', text: txt });
    $('chatIn').value = '';
    persistState();
    setTimeout(() => {
      state.chat.push({ role: 'bot', text: conciergeReply(txt, h) });
      persistState();
      renderConcierge(h);
    }, 420);
    renderConcierge(h);
  };
  $('chatSend').addEventListener('click', send);
  $('chatIn').addEventListener('keydown', (e) => { if (e.key === 'Enter') send(); });
  app.querySelector('[data-handoff]').addEventListener('click', () => {
    hostBridge('openChat', { handle: h.concierge.handle, displayName: pickLang(h.concierge.displayName) });
  });
  const chatBox = $('chat');
  chatBox.scrollTop = chatBox.scrollHeight;
}

function bubbleHtml(m) {
  return `<div class="bubble bubble--${m.role === 'me' ? 'me' : 'bot'}">${escapeHtml(m.text)}</div>`;
}

function conciergeReply(text, h) {
  const s = text.toLowerCase();
  // Keyword detection — German + English + Arabic transliteration/script.
  if (/(tisch|reservier|restaurant|table|reserve|طاولة|مطعم|حجز)/.test(s)) return t('replyTable');
  if (/(taxi|wasser|boot|vaporetto|transfer|تاكسي|قارب)/.test(s)) return t('replyTaxi');
  if (/(spa|massage|wellness|سبا|تدليك|عافية)/.test(s)) return t('replySpa');
  if (/(check.?out|spät|late|متأخر|مغادرة)/.test(s)) return t('replyCheckout');
  if (/(danke|grazie|merci|thanks|thank you|شكرا|شكراً)/.test(s)) return t('replyThanks');
  return t('replyGeneric')(pickLang(h.name));
}

// ---------- Bridge to host ----------
function hostBridge(action, payload) {
  const msg = JSON.stringify({ action, payload, from: 'miniapp.hotels' });
  try {
    if (window.ShamellHost && typeof window.ShamellHost.postMessage === 'function') {
      window.ShamellHost.postMessage(msg);
      return;
    }
  } catch (_) { /* fall through */ }
  if (action === 'openPayments')
    showToast(t('demoPay')(formatPrice(payload.amount, payload.currency)));
  else if (action === 'openChat')
    showToast(t('demoChat')(payload.displayName));
  else if (action === 'share')
    showToast(t('demoShare'));
  // createBooking/createOrder are silent demo-side — toast only on the
  // payment hand-off so we don't double-pop.
}

function shareCurrent() {
  const h = state.selectedHotel;
  if (!h) {
    hostBridge('share', { title: t('navTitle') });
  } else {
    hostBridge('share', { title: pickLang(h.name), hotelId: h.id });
  }
}

// ---------- Helpers ----------
function setTitle(txt) { navTitle.textContent = txt; }

function showToast(txt) {
  toastEl.textContent = txt;
  toastEl.hidden = false;
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => { toastEl.hidden = true; }, 2400);
}

function today(offsetDays) {
  const d = new Date();
  d.setDate(d.getDate() + (offsetDays || 0));
  return d.toISOString().slice(0, 10);
}
function nightsBetween(a, b) {
  const da = new Date(a), db = new Date(b);
  return Math.round((db - da) / 86400000);
}
function intlLocale() {
  const l = lc();
  return l === 'ar' ? 'ar-SA' : (l === 'en' ? 'en-US' : 'de-DE');
}
function formatPrice(n, cur) {
  return new Intl.NumberFormat(intlLocale(), { style: 'currency', currency: cur || 'EUR', maximumFractionDigits: 0 }).format(n);
}
function formatCurrencySymbol(n, cur) {
  return new Intl.NumberFormat(intlLocale(), { style: 'currency', currency: cur || 'EUR', maximumFractionDigits: 0 }).format(n);
}
function formatDate(iso) {
  return new Intl.DateTimeFormat(intlLocale(), { weekday: 'short', day: '2-digit', month: 'short' }).format(new Date(iso));
}
function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
}
function escapeAttr(s) { return escapeHtml(s); }

function persistState() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({
      search: state.search, cart: state.cart, chat: state.chat,
    }));
  } catch (_) { /* storage may be disabled — non-fatal */ }
}
function restoreState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return;
    const saved = JSON.parse(raw);
    if (saved.search) Object.assign(state.search, saved.search);
    if (saved.cart) state.cart = saved.cart;
    if (saved.chat && Array.isArray(saved.chat)) state.chat = saved.chat;
  } catch (_) { /* corrupt — start fresh */ }
}
