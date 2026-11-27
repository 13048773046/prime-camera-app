(() => {
  'use strict';
  const API = '';
  const TOKEN_KEY = 'prime_admin_token_v1';
  const $ = (id) => document.getElementById(id);
  const state = { token: localStorage.getItem(TOKEN_KEY) || '', admin: null, view: 'dashboard' };
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fmtDate = (v) => String(v || '').replace('T', ' ').slice(0, 16);
  function toast(text) {
    const el = $('toast'); el.textContent = text; el.classList.add('show');
    clearTimeout(toast.t); toast.t = setTimeout(() => el.classList.remove('show'), 2200);
  }
  async function api(path, options = {}) {
    const headers = { ...(options.headers || {}) };
    if (state.token) headers.Authorization = `Bearer ${state.token}`;
    if (options.body && typeof options.body !== 'string') {
      headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(options.body);
    }
    const res = await fetch(`${API}/admin/api${path}`, { ...options, headers });
    if (res.status === 401) { logout(true); throw new Error('登录已失效'); }
    const body = await res.json().catch(() => ({ code: 1, message: '响应解析失败' }));
    if (body.code !== 0) throw new Error(body.message || '请求失败');
    return body.data;
  }

  function showLogin() {
    $('loginView').style.display = 'grid';
    $('appView').hidden = true;
  }
  function showApp() {
    $('loginView').style.display = 'none';
    $('appView').hidden = false;
  }
  function logout(clear = true) {
    if (clear) { state.token = ''; localStorage.removeItem(TOKEN_KEY); }
    showLogin();
  }

  async function login() {
    const username = $('loginUser').value.trim();
    const password = $('loginPass').value;
    $('loginHint').textContent = '';
    try {
      const data = await api('/login', { method: 'POST', body: { username, password } });
      state.token = data.token;
      state.admin = data.name;
      localStorage.setItem(TOKEN_KEY, state.token);
      $('loginPass').value = '';
      showApp();
      await loadOverview();
    } catch (err) { $('loginHint').textContent = err.message || '登录失败'; }
  }

  async function loadOverview() {
    try {
      const d = await api('/overview');
      $('mUsers').textContent = d.users ?? '--';
      $('mNewUsers').textContent = `今日新增 ${d.new_users_today ?? 0}`;
      $('mPro').textContent = d.pro_users ?? '--';
      $('mScan').textContent = d.scan_today ?? '--';
      $('mOrders').textContent = d.orders_today ?? 0;
      $('mRevenue').textContent = `收入 ¥ ${Number(d.revenue_today || 0).toFixed(2)} · 已付 ${d.paid_orders_today ?? 0}`;
      $('domainValue').textContent = d.public_base_url || '--';
      $('versionValue').textContent = d.app_version || '--';
      $('maintenanceValue').textContent = d.maintenance ? '维护中' : '正常';
      $('maintenanceValue').className = d.maintenance ? 'pill warn' : 'pill ok';
      $('announcementValue').textContent = d.announcement || '—';
      $('sideDomain').textContent = String(d.public_base_url || '').replace(/^https?:\/\//, '');
      $('footerDomain').textContent = String(d.public_base_url || '').replace(/^https?:\/\//, '');
      const usage = await api('/usage');
      drawChart(usage.items || []);
      const events = await api('/events?limit=8');
      renderRecent(events.items || []);
    } catch (err) { toast(err.message); }
  }
  function drawChart(items) {
    const max = Math.max(1, ...items.map((x) => Math.max(x.scans || 0, x.new_users || 0, x.orders || 0)));
    $('usageChart').innerHTML = items.map((x) => {
      const scanH = Math.round(((x.scans || 0) / max) * 100);
      const userH = Math.round(((x.new_users || 0) / max) * 100);
      return `<div class="bar" style="height:${Math.max(2, scanH)}%" title="${esc(x.date)} · scan ${x.scans || 0} · 新增 ${x.new_users || 0} · 订单 ${x.orders || 0}"><i style="height:${Math.max(0, userH)}%;opacity:.75"></i></div>`;
    }).join('');
  }
  function renderRecent(items) {
    $('recentEvents').innerHTML = items.length ? items.map((e) => {
      const payload = typeof e.payload === 'object' ? JSON.stringify(e.payload) : String(e.payload || '');
      return `<div class="event"><b>${esc(e.kind)}</b><span>${esc(payload).slice(0, 160)}</span><time>${esc(fmtDate(e.created_at))}</time></div>`;
    }).join('') : '<div class="muted">暂无事件</div>';
  }

  async function loadUsers() {
    const q = $('userSearch').value.trim();
    try {
      const d = await api(`/users?q=${encodeURIComponent(q)}&limit=100`);
      $('userTotal').textContent = `共 ${d.total} 个用户`;
      $('usersBody').innerHTML = (d.items || []).map((u) => `<tr>
        <td><b>${esc(u.username || '未命名')}</b><br><span class="muted">${esc((u.id || '').slice(0, 10))}</span></td>
        <td>${esc(u.phone || '—')}</td>
        <td>${u.vip_expire_at ? `<span class="pill pro">${esc(fmtDate(u.vip_expire_at))}</span>` : '<span class="muted">未开通</span>'}</td>
        <td><span class="pill ${u.status === '正常' ? 'ok' : 'danger'}">${esc(u.status)}</span></td>
        <td>${esc(fmtDate(u.created_at))}</td>
        <td><div class="row-actions">
          <button class="mini" data-vip="${esc(u.id)}">送 Pro</button>
          <button class="mini" data-disable="${esc(u.id)}" data-disabled="${u.disabled_at ? 1 : 0}">${u.disabled_at ? '解禁' : '禁用'}</button>
          <button class="mini danger" data-delete="${esc(u.id)}">删除</button>
        </div></td>
      </tr>`).join('') || '<tr><td colspan="6" class="muted">没有用户</td></tr>';
    } catch (err) { toast(err.message); }
  }
  async function userAction(e) {
    const vip = e.target.closest('[data-vip]');
    const dis = e.target.closest('[data-disable]');
    const del = e.target.closest('[data-delete]');
    try {
      if (vip) {
        const days = Number(prompt('赠送 Pro 天数', '30') || 0);
        if (!days) return;
        await api(`/users/${vip.dataset.vip}/vip`, { method: 'POST', body: { days } });
        toast(`已赠送 ${days} 天 Pro`);
      } else if (dis) {
        const disable = dis.dataset.disabled === '0';
        await api(`/users/${dis.dataset.disable}/status`, { method: 'POST', body: { disabled: disable } });
        toast(disable ? '已禁用' : '已解禁');
      } else if (del) {
        if (!confirm('软删除这个用户？')) return;
        await api(`/users/${del.dataset.delete}`, { method: 'DELETE' });
        toast('已删除');
      }
      await loadUsers();
    } catch (err) { toast(err.message); }
  }

  async function loadOrders() {
    const status = $('orderStatus').value;
    try {
      const d = await api(`/orders?status=${encodeURIComponent(status)}&limit=100`);
      $('ordersBody').innerHTML = (d.items || []).map((o) => `<tr>
        <td><span class="muted">${esc(o.out_trade_no)}</span></td>
        <td>${esc(o.phone || o.username || o.user_id)}</td>
        <td>${esc(o.product_id)}</td>
        <td>¥ ${Number(o.amount || 0).toFixed(2)}</td>
        <td><span class="pill ${o.status === 'paid' ? 'ok' : o.status === 'refunded' ? 'danger' : 'warn'}">${esc(o.status)}</span></td>
        <td>${esc(fmtDate(o.created_at))}</td>
        <td><div class="row-actions"><button class="mini" data-confirm="${esc(o.out_trade_no)}">确认支付</button><button class="mini danger" data-refund="${esc(o.out_trade_no)}">退款</button></div></td>
      </tr>`).join('') || '<tr><td colspan="7" class="muted">没有订单</td></tr>';
    } catch (err) { toast(err.message); }
  }
  async function orderAction(e) {
    const c = e.target.closest('[data-confirm]');
    const r = e.target.closest('[data-refund]');
    try {
      if (c) { await api(`/orders/${c.dataset.confirm}/confirm`, { method: 'POST' }); toast('订单已标记支付'); }
      if (r) { if (!confirm('标记退款？不会调用真实支付通道。')) return; await api(`/orders/${r.dataset.refund}/refund`, { method: 'POST' }); toast('已标记退款'); }
      await loadOrders();
    } catch (err) { toast(err.message); }
  }

  async function loadCodes() {
    try {
      const d = await api('/redeem-codes');
      $('codesBody').innerHTML = (d.items || []).map((c) => `<tr>
        <td><b>${esc(c.code)}</b></td><td>${c.days} 天</td>
        <td>${c.used_count} / ${c.max_uses}</td>
        <td>${esc(fmtDate(c.expires_at))}</td>
        <td><span class="pill ${c.active ? 'ok' : 'danger'}">${c.active ? '可用' : '已停用'}</span></td>
        <td><button class="mini danger" data-disablecode="${esc(c.code)}">停用</button></td>
      </tr>`).join('') || '<tr><td colspan="6" class="muted">还没生成兑换码</td></tr>';
    } catch (err) { toast(err.message); }
  }
  async function genCodes() {
    try {
      const data = await api('/redeem-codes', {
        method: 'POST',
        body: { days: Number($('codeDays').value), count: Number($('codeCount').value), max_uses: Number($('codeUses').value), expires_days: Number($('codeExpires').value) },
      });
      $('codeHint').textContent = `已生成 ${data.items.length} 个，可直接复制发给用户`;
      await loadCodes();
    } catch (err) { $('codeHint').textContent = err.message; }
  }

  async function loadSettings() {
    try {
      const s = await api('/settings');
      $('setBaseUrl').value = s.public_base_url || '';
      $('setAppVersion').value = s.app_version || '';
      $('setDownloadUrl').value = s.download_url || '';
      $('setFreeCount').value = s.free_ai_count || '5';
      $('setProCount').value = s.pro_ai_count || '9999';
      $('setSupportEmail').value = s.support_email || '';
      $('setDouyin').value = s.support_douyin || '';
      $('setRedbook').value = s.support_xiaohongshu || '';
      $('setWatermark').value = s.watermark_styles || '';
      $('setAnnouncement').value = s.announcement || '';
      $('setMaintenance').checked = s.maintenance === '1';
      $('setGlobal').checked = s.global_enabled !== '0';
      $('setRedeem').checked = s.show_redeem_entry !== '0';
    } catch (err) { toast(err.message); }
  }
  async function saveSettings() {
    try {
      await api('/settings', {
        method: 'PUT',
        body: { values: {
          public_base_url: $('setBaseUrl').value.trim(),
          app_version: $('setAppVersion').value.trim(),
          download_url: $('setDownloadUrl').value.trim(),
          free_ai_count: $('setFreeCount').value.trim(),
          pro_ai_count: $('setProCount').value.trim(),
          support_email: $('setSupportEmail').value.trim(),
          support_douyin: $('setDouyin').value.trim(),
          support_xiaohongshu: $('setRedbook').value.trim(),
          watermark_styles: $('setWatermark').value.trim(),
          announcement: $('setAnnouncement').value.trim(),
          maintenance: $('setMaintenance').checked ? '1' : '0',
          global_enabled: $('setGlobal').checked ? '1' : '0',
          show_redeem_entry: $('setRedeem').checked ? '1' : '0',
        } },
      });
      $('settingsHint').textContent = '已保存；所有接口按公开域名派生';
      await loadOverview();
    } catch (err) { $('settingsHint').textContent = err.message; }
  }

  async function loadPersona() {
    try {
      const p = await api('/persona');
      $('personaName').value = p.name || '';
      $('personaRole').value = p.role || '';
      $('personaPrompt').value = p.prompt || '';
    } catch (err) { toast(err.message); }
  }
  async function savePersona() {
    try {
      await api('/persona', { method: 'PUT', body: { name: $('personaName').value, role: $('personaRole').value, prompt: $('personaPrompt').value } });
      $('personaHint').textContent = '人格已保存';
    } catch (err) { $('personaHint').textContent = err.message; }
  }

  async function loadFilters() {
    try {
      const d = await api('/filters');
      const items = d.items || [];
      $('filterAdmin').innerHTML = items.map((f) => `<span>${esc(f.name || f.id)} ${f.pro ? '· PRO' : ''}</span>`).join('');
      $('filterJson').value = JSON.stringify(items, null, 2);
    } catch (err) { toast(err.message); }
  }
  async function saveFilters() {
    try {
      const items = JSON.parse($('filterJson').value);
      if (!Array.isArray(items)) throw new Error('JSON 必须是数组');
      await api('/filters', { method: 'PUT', body: { items } });
      $('filterHint').textContent = `已保存 ${items.length} 款`;
      await loadFilters();
    } catch (err) { $('filterHint').textContent = err.message; }
  }

  async function loadEvents() {
    try {
      const kind = $('eventKind').value;
      const d = await api(`/events?kind=${encodeURIComponent(kind)}&limit=200`);
      $('eventsBody').innerHTML = (d.items || []).map((e) => {
        const payload = typeof e.payload === 'object' ? JSON.stringify(e.payload) : String(e.payload || '');
        return `<tr><td>${esc(fmtDate(e.created_at))}</td><td><span class="pill">${esc(e.kind)}</span></td><td>${esc(payload).slice(0, 260)}</td></tr>`;
      }).join('') || '<tr><td colspan="3" class="muted">没有事件</td></tr>';
    } catch (err) { toast(err.message); }
  }

  const titles = {
    dashboard: ['总览', '今天，谁在用 PRIME？'],
    users: ['用户', '用户与权益'],
    orders: ['订单', 'Pro 订单与模拟支付'],
    redeem: ['兑换码', '生成、停用与追踪'],
    settings: ['站点设置', '域名、版本与开关'],
    persona: ['AI 人格', '流小萤的说话方式'],
    filters: ['滤镜库', '27 款胶片的运营台'],
    events: ['审计日志', '谁在什么时候做了什么'],
  };
  async function showView(view) {
    state.view = view;
    document.querySelectorAll('.nav-item').forEach((n) => n.classList.toggle('active', n.dataset.view === view));
    document.querySelectorAll('.panel').forEach((p) => p.classList.toggle('active', p.id === `panel-${view}`));
    $('crumb').textContent = titles[view][0];
    $('pageTitle').textContent = titles[view][1];
    if (view === 'dashboard') await loadOverview();
    if (view === 'users') await loadUsers();
    if (view === 'orders') await loadOrders();
    if (view === 'redeem') await loadCodes();
    if (view === 'settings') await loadSettings();
    if (view === 'persona') await loadPersona();
    if (view === 'filters') await loadFilters();
    if (view === 'events') await loadEvents();
  }

  function bind() {
    $('loginBtn').addEventListener('click', login);
    $('loginPass').addEventListener('keydown', (e) => { if (e.key === 'Enter') login(); });
    $('logoutBtn').addEventListener('click', () => logout(true));
    document.querySelectorAll('.nav-item').forEach((n) => n.addEventListener('click', () => { showView(n.dataset.view); document.querySelector('.sidebar').classList.remove('open'); }));
    $('menuToggle').addEventListener('click', () => document.querySelector('.sidebar').classList.toggle('open'));
    document.querySelectorAll('[data-goto]').forEach((b) => b.addEventListener('click', () => showView(b.dataset.goto)));
    $('userSearchBtn').addEventListener('click', loadUsers);
    $('userSearch').addEventListener('keydown', (e) => { if (e.key === 'Enter') loadUsers(); });
    $('usersBody').addEventListener('click', userAction);
    $('orderFilterBtn').addEventListener('click', loadOrders);
    $('ordersBody').addEventListener('click', orderAction);
    $('genCodesBtn').addEventListener('click', genCodes);
    $('codesBody').addEventListener('click', async (e) => {
      const b = e.target.closest('[data-disablecode]');
      if (!b) return;
      try { await api(`/redeem-codes/${encodeURIComponent(b.dataset.disablecode)}/disable`, { method: 'POST' }); toast('已停用'); await loadCodes(); }
      catch (err) { toast(err.message); }
    });
    $('saveSettingsBtn').addEventListener('click', saveSettings);
    $('savePersonaBtn').addEventListener('click', savePersona);
    $('saveFiltersBtn').addEventListener('click', saveFilters);
    $('eventFilterBtn').addEventListener('click', loadEvents);
    $('eventKind').addEventListener('change', loadEvents);
    setInterval(() => { if (state.token && state.view === 'dashboard') loadOverview().catch(() => {}); }, 30000);
  }

  bind();
  if (state.token) { showApp(); loadOverview().catch(() => logout(true)); }
  else showLogin();
})();
