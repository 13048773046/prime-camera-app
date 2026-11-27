(() => {
  'use strict';
  const API = location.protocol.startsWith('http') ? location.origin : 'https://uosar.yosar.cloud';
  const LS = {
    photos: 'prime_h5_photos_v1',
    settings: 'prime_h5_settings_v1',
    token: 'prime_h5_token_v1',
    profile: 'prime_h5_profile_v1',
  };
  const $ = (id) => document.getElementById(id);
  const sceneImage = new Image();
  sceneImage.src = '/assets/scene.jpg';
  const state = {
    stream: null,
    facing: 'environment',
    filter: 'none',
    scene: 'portrait',
    autoAi: false,
    aiTimer: null,
    scanning: false,
    photos: [],
    selected: null,
    imported: null,
    token: localStorage.getItem(LS.token) || '',
    profile: null,
    settings: { grid: false, mirror: false, watermark: true, autoAi: false, scene: 'portrait' },
  };

  const FILTERS = [
    { id: 'none', name: '原片', cat: '原片', css: '', color: 'linear-gradient(135deg,#e7b27e,#5f3945)' },
    { id: 'clear', name: '清透', cat: '原片', css: 'contrast(1.08) saturate(1.06) brightness(1.02)', color: 'linear-gradient(135deg,#dfe9e2,#7d8c86)' },
    { id: 'warm', name: '暖调', cat: '原片', css: 'sepia(.18) saturate(1.18) brightness(1.03)', color: 'linear-gradient(135deg,#e5bc72,#8f6c32)' },
    { id: 'cool', name: '冷调', cat: '原片', css: 'hue-rotate(-6deg) saturate(.95) brightness(1.02)', color: 'linear-gradient(135deg,#b9d9e7,#4e6478)' },
    { id: 'mono', name: '黑白', cat: '黑白', css: 'grayscale(1) contrast(1.05)', color: 'linear-gradient(135deg,#c9c9c9,#3a3a3a)' },
    { id: 'doka_s50', name: 'S50', cat: 'Doka', css: 'brightness(1.12) saturate(.92) contrast(.94) sepia(.06)', color: 'linear-gradient(135deg,#dce6e0,#788a84)', pro: true },
    { id: 'doka_s100', name: 'S100', cat: 'Doka', css: 'brightness(1.06) saturate(1.02) contrast(1.02)', color: 'linear-gradient(135deg,#ddd2be,#7f6b58)', pro: true },
    { id: 'doka_s160', name: 'S160', cat: 'Doka', css: 'saturate(1.06) contrast(1.03) hue-rotate(-3deg)', color: 'linear-gradient(135deg,#c6d7c1,#5f7a63)', pro: true },
    { id: 'doka_s200', name: 'S200', cat: 'Doka', css: 'saturate(.98) contrast(1.12) brightness(.98)', color: 'linear-gradient(135deg,#b9b4a7,#514a42)', pro: true },
    { id: 'doka_s400', name: 'S400', cat: 'Doka', css: 'saturate(1.04) contrast(1.15) sepia(.08)', color: 'linear-gradient(135deg,#c09b7c,#5a3730)', pro: true },
    { id: 'f160c', name: 'F160C', cat: 'F 系列', css: 'saturate(1.08) contrast(1.04) hue-rotate(8deg)', color: 'linear-gradient(135deg,#b7d1cb,#4d716b)', pro: true },
    { id: 'f400h', name: 'F400H', cat: 'F 系列', css: 'saturate(1.1) contrast(.96) brightness(1.04) hue-rotate(10deg)', color: 'linear-gradient(135deg,#a9c1db,#4a5f7a)', pro: true },
    { id: 'fc200', name: 'FC200', cat: 'F 系列', css: 'sepia(.1) saturate(1.08) contrast(1.05)', color: 'linear-gradient(135deg,#d9c7a9,#7b6245)', pro: true },
    { id: 'fcc', name: 'FCC', cat: 'F 系列', css: 'saturate(1.16) contrast(1.12)', color: 'linear-gradient(135deg,#b0c9c8,#425f61)', pro: true },
    { id: 'classic_chrome', name: 'Classic Chrome', cat: 'F 系列', css: 'saturate(.9) contrast(1.1) sepia(.04)', color: 'linear-gradient(135deg,#c2c7bf,#5c625d)', pro: true },
    { id: 'classic_neg', name: 'Classic Neg', cat: 'F 系列', css: 'saturate(1.06) contrast(1.08) hue-rotate(-8deg)', color: 'linear-gradient(135deg,#ba9caf,#573747)', pro: true },
    { id: 'pro_neg', name: 'Pro Neg', cat: 'F 系列', css: 'saturate(1.02) contrast(.98) sepia(.05)', color: 'linear-gradient(135deg,#d0c0b2,#6d5b4c)', pro: true },
    { id: 'provia', name: 'Provia', cat: 'F 系列', css: 'contrast(1.06) saturate(1.02)', color: 'linear-gradient(135deg,#c2d3d7,#57696e)', pro: true },
    { id: 'velvia', name: 'Velvia', cat: 'F 系列', css: 'saturate(1.3) contrast(1.16)', color: 'linear-gradient(135deg,#c6d08f,#586329)', pro: true },
    { id: 'astia', name: 'Astia', cat: 'F 系列', css: 'saturate(1.05) contrast(1.02) brightness(1.04)', color: 'linear-gradient(135deg,#e0c0a8,#7d5a48)', pro: true },
    { id: 'kodak_gold', name: 'Gold 200', cat: 'Kodak', css: 'sepia(.16) saturate(1.12) contrast(1.04)', color: 'linear-gradient(135deg,#e5bc72,#8f6c32)', pro: true },
    { id: 'portra160', name: 'Portra 160', cat: 'Kodak', css: 'saturate(.96) contrast(.96) brightness(1.05) sepia(.03)', color: 'linear-gradient(135deg,#d9c2ad,#775f4c)', pro: true },
    { id: 'portra400', name: 'Portra 400', cat: 'Kodak', css: 'sepia(.08) saturate(1.04) contrast(1.0)', color: 'linear-gradient(135deg,#e0b699,#7d5547)', pro: true },
    { id: 'ektar', name: 'Ektar 100', cat: 'Kodak', css: 'saturate(1.2) contrast(1.15)', color: 'linear-gradient(135deg,#c59a9b,#663b42)', pro: true },
    { id: 'agfa_ap100', name: 'APX 100', cat: 'Agfa', css: 'grayscale(1) contrast(1.18)', color: 'linear-gradient(135deg,#bdbdbd,#2e2e2e)', pro: true },
    { id: 'agfa_vista', name: 'Vista 800', cat: 'Agfa', css: 'saturate(1.06) contrast(1.02) hue-rotate(-10deg) sepia(.05)', color: 'linear-gradient(135deg,#c9a9bd,#5a3550)', pro: true },
    { id: 'bw_high', name: '黑白 400', cat: '黑白', css: 'grayscale(1) contrast(1.22)', color: 'linear-gradient(135deg,#d0d0d0,#202020)', pro: true },
  ];
  const CORE_IDS = ['none', 'clear', 'warm', 'cool', 'mono', 'doka_s100', 'portra400', 'kodak_gold', 'classic_chrome'];
  const filterById = (id) => FILTERS.find((f) => f.id === id) || FILTERS[0];

  function showToast(text) {
    const el = $('toast');
    el.textContent = text;
    el.classList.add('show');
    clearTimeout(showToast.t);
    showToast.t = setTimeout(() => el.classList.remove('show'), 2200);
  }

  function loadSettings() {
    try {
      state.settings = { ...state.settings, ...JSON.parse(localStorage.getItem(LS.settings) || '{}') };
    } catch (_) {}
    state.scene = state.settings.scene || 'portrait';
    state.autoAi = !!state.settings.autoAi;
    $('setGrid').checked = !!state.settings.grid;
    $('setMirror').checked = !!state.settings.mirror;
    $('setWatermark').checked = state.settings.watermark !== false;
    $('setAutoAi').checked = state.autoAi;
    $('setScene').value = state.scene;
    $('grid').classList.toggle('show', !!state.settings.grid);
    $('autoAiBtn').classList.toggle('on', state.autoAi);
    setSceneLabel();
  }
  function saveSettings() {
    localStorage.setItem(LS.settings, JSON.stringify(state.settings));
    $('grid').classList.toggle('show', !!state.settings.grid);
    $('autoAiBtn').classList.toggle('on', state.autoAi);
    setSceneLabel();
    if (state.autoAi) startAutoAi(); else stopAutoAi();
  }
  function setSceneLabel() {
    const names = { portrait: '人像场景', landscape: '风景场景', still: '静物场景', general: '自动场景' };
    $('sceneLabel').textContent = names[state.scene] || '自动场景';
  }
  function applyFilter(id) {
    state.filter = id;
    const f = filterById(id);
    $('video').style.filter = f.css;
    $('fallback').style.filter = f.css;
    $('filterName').textContent = f.name;
    $('currentSwatch').style.background = f.color;
    renderFilmStrip();
    document.querySelectorAll('.filter-card').forEach((el) => el.classList.toggle('on', el.dataset.id === id));
  }
  function renderFilmStrip() {
    $('filmStrip').innerHTML = CORE_IDS.map((id) => {
      const f = filterById(id);
      return `<button class="film-pill ${f.id === state.filter ? 'on' : ''}" data-filter="${f.id}"><i style="background:${f.color}"></i>${f.name}</button>`;
    }).join('');
}
  function renderFilterSheet(cat = '全部') {
    const cats = ['全部', ...new Set(FILTERS.map((f) => f.cat))];
    $('filterCats').innerHTML = cats.map((c) => `<button class="${c === cat ? 'on' : ''}" data-cat="${c}">${c}</button>`).join('');
    $('filterGrid').innerHTML = FILTERS.filter((f) => cat === '全部' || f.cat === cat).map((f) => `
      <button class="filter-card ${f.id === state.filter ? 'on' : ''}" data-id="${f.id}">
        <div class="thumb" style="background:${f.color}">${f.pro ? '<span class="pro">PRO</span>' : ''}</div>
        <b>${f.name}</b><small>${f.pro ? 'Pro 胶片' : '基础胶片'}</small>
      </button>`).join('');
  }

  async function initCamera(facing = state.facing) {
    state.facing = facing;
    $('cameraState').textContent = '正在打开相机…';
    $('fallback').style.display = 'block';
    try {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) throw new Error('无摄像头 API');
      if (state.stream) state.stream.getTracks().forEach((t) => t.stop());
      state.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: facing, width: { ideal: 1280 }, height: { ideal: 1280 } },
        audio: false,
      });
      const video = $('video');
      video.srcObject = state.stream;
      video.style.transform = facing === 'user' ? 'scaleX(-1)' : 'none';
      await video.play().catch(() => {});
      $('fallback').style.display = 'none';
      $('cameraState').textContent = '相机已就绪 · 3:4';
    } catch (err) {
      $('video').srcObject = null;
      $('fallback').style.display = 'block';
      $('cameraState').textContent = '未授权相机 · 可导入照片或点“翻转”重试';
      showToast('浏览器没有拿到相机权限；仍可导入照片做 AI 构图。');
    }
  }
  function stopAutoAi() {
    if (state.aiTimer) clearInterval(state.aiTimer);
    state.aiTimer = null;
  }
  function startAutoAi() {
    stopAutoAi();
    if (!state.autoAi) return;
    state.aiTimer = setInterval(() => {
      if (!document.hidden && !state.scanning && document.querySelector('#view-camera').classList.contains('active')) scanAi(true);
    }, 2200);
  }

  function drawFrameForCapture(withWatermark = true) {
    const canvas = document.createElement('canvas');
    canvas.width = 720;
    canvas.height = 960;
    const ctx = canvas.getContext('2d');
    const src = $('video');
    const hasVideo = src && src.videoWidth > 0 && state.stream;
    if (hasVideo) {
      const sw = src.videoWidth, sh = src.videoHeight;
      const scale = Math.max(canvas.width / sw, canvas.height / sh);
      const dw = sw * scale, dh = sh * scale;
      ctx.save();
      if (state.settings.mirror && state.facing === 'user') {
        ctx.translate(canvas.width, 0);
        ctx.scale(-1, 1);
      }
      ctx.filter = withWatermark ? (filterById(state.filter).css || 'none') : 'none';
      ctx.drawImage(src, (canvas.width - dw) / 2, (canvas.height - dh) / 2, dw, dh);
      ctx.restore();
    } else {
      const img = state.imported || sceneImage;
      try {
        if (!img.width || !img.height) throw new Error('image not ready');
        const scale = Math.max(canvas.width / img.width, canvas.height / img.height);
        ctx.filter = withWatermark ? (filterById(state.filter).css || 'none') : 'none';
        ctx.drawImage(img, (canvas.width - img.width * scale) / 2, (canvas.height - img.height * scale) / 2, img.width * scale, img.height * scale);
      } catch (_) {
        ctx.fillStyle = '#202020';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
      }
    }
    if (withWatermark && state.settings.watermark !== false) {
      ctx.filter = 'none';
      const t = new Date();
      const stamp = `${t.getFullYear()}.${String(t.getMonth() + 1).padStart(2, '0')}.${String(t.getDate()).padStart(2, '0')}  PRIME`;
      ctx.font = '18px -apple-system,BlinkMacSystemFont,sans-serif';
      ctx.fillStyle = 'rgba(255,255,255,.78)';
      ctx.textAlign = 'right';
      ctx.fillText(stamp, canvas.width - 18, canvas.height - 18);
    }
    return canvas;
  }
  async function capture() {
    const canvas = drawFrameForCapture(true);
    const data = canvas.toDataURL('image/jpeg', 0.82);
    const photo = { id: Date.now().toString(36), data, time: new Date().toISOString(), filter: state.filter };
    state.photos.unshift(photo);
    state.photos = state.photos.slice(0, 10);
    try { localStorage.setItem(LS.photos, JSON.stringify(state.photos)); } catch (_) { showToast('本地空间不足，照片未保存'); return; }
    flashPreview();
    showToast('已拍下 · 相册里可查看');
    renderGallery();
  }
  function flashPreview() {
    const p = $('preview');
    p.animate([{ opacity: 1 }, { opacity: 0.25 }, { opacity: 1 }], { duration: 260 });
  }
  function canvasBlob(canvas) {
    return new Promise((resolve) => canvas.toBlob((b) => resolve(b), 'image/jpeg', 0.72));
  }
  function setTargetBox(rect) {
    if (!rect || !rect.W) { $('targetBox').classList.remove('show'); return; }
    const el = $('targetBox');
    el.style.left = `${rect.X * 100}%`;
    el.style.top = `${rect.Y * 100}%`;
    el.style.width = `${rect.W * 100}%`;
    el.style.height = `${rect.H * 100}%`;
    el.classList.add('show');
  }
  function applyScan(data) {
    if (!data) return;
    const rect = data.SubAreaRectNorm || {};
    setTargetBox(rect);
    const reason = data.ComposeReason || '把主体放进双环，停半秒再按快门';
    $('aiLine').querySelector('p').textContent = reason;
    const m = reason.match(/约\s*([0-9.]+)\s*米/);
    $('distanceCard').querySelector('strong').textContent = m ? `${m[1]}m` : 'AI';
    $('distanceCard').querySelector('span').textContent = m ? '距离刚好 · 跟随目标环' : '构图已更新';
    const filter = (data.AiCameraFilter || {}).FilterName || '';
    const idMap = {
      '清透': 'clear', '暖调': 'warm', '冷调': 'cool', '黑白': 'mono', '原片': 'none',
      'Doka S50': 'doka_s50', 'Doka S100': 'doka_s100', 'Doka S160': 'doka_s160',
      'Doka S200': 'doka_s200', 'Doka S400': 'doka_s400',
      'F160C': 'f160c', 'F400H': 'f400h', 'FC200': 'fc200', 'FCC': 'fcc',
      'Classic Chrome': 'classic_chrome', 'Classic Neg': 'classic_neg',
      'Pro Neg': 'pro_neg', 'Provia': 'provia', 'Velvia': 'velvia', 'Astia': 'astia',
      'Gold 200': 'kodak_gold', 'Portra 160': 'portra160', 'Portra 400': 'portra400',
      'Ektar 100': 'ektar', 'APX 100': 'agfa_ap100', 'Vista 800': 'agfa_vista',
      '黑白 400': 'bw_high',
    };
    if (idMap[filter]) applyFilter(idMap[filter]);
    if (data.AiCameraFilters && data.AiCameraFilters.length) {
      const names = data.AiCameraFilters.map((x) => x.FilterName).filter(Boolean).slice(0, 3);
      if (names.length) showToast(`AI 推荐：${names.join(' / ')}`);
    }
  }
  async function scanAi(auto = false) {
    if (state.scanning) return;
    state.scanning = true;
    $('aiBtn').classList.add('scanning');
    if (!auto) $('tipText').textContent = '正在上传当前帧…';
    try {
      const canvas = drawFrameForCapture(false);
      const blob = await canvasBlob(canvas);
      const fd = new FormData();
      fd.append('file', blob, 'frame.jpg');
      fd.append('shoot_type', 'preview');
      fd.append('direction', state.scene);
      fd.append('comp_scene', state.scene);
      fd.append('scan_focal_length', '1.0');
      fd.append('timestamp', Date.now().toString());
      fd.append('recommend_mode', 'auto');
      fd.append('ai_filter_preferences', JSON.stringify({ scenes: [state.scene], series: ['Doka'] }));
      fd.append('language', 'zh');
      fd.append('region', 'CN');
      fd.append('distribution', 'h5');
      fd.append('aspect', '3:4');
      const res = await fetch(`${API}/ai_camera/v2`, { method: 'POST', body: fd });
      const body = await res.json();
      if (body.code !== 0 || !body.data) throw new Error(body.message || 'scan failed');
      applyScan(body.data);
      $('tipText').textContent = auto ? 'AI 自动跟随中' : '已更新构图';
    } catch (err) {
      $('tipText').textContent = 'AI 暂不可用 · 可先拍';
      if (!auto) showToast('AI 构图服务未连通；检查 /ai_camera/v2 与域名配置');
    } finally {
      state.scanning = false;
      $('aiBtn').classList.remove('scanning');
    }
  }

  function renderGallery() {
    $('galleryCount').textContent = `${state.photos.length} 张照片`;
    $('galleryEmpty').classList.toggle('show', state.photos.length === 0);
    $('galleryGrid').innerHTML = state.photos.map((p) => `<button class="gallery-item" data-photo="${p.id}"><img src="${p.data}" alt=""><span>${filterById(p.filter).name}</span></button>`).join('');
    try { localStorage.setItem(LS.photos, JSON.stringify(state.photos)); } catch (_) {}
  }
  function openPhoto(id) {
    const p = state.photos.find((x) => x.id === id);
    if (!p) return;
    state.selected = p;
    $('photoBig').src = p.data;
    $('photoModal').classList.add('show');
  }
  function downloadPhoto() {
    if (!state.selected) return;
    const a = document.createElement('a');
    a.href = state.selected.data;
    a.download = `prime-${state.selected.id}.jpg`;
    a.click();
  }
  async function sharePhoto() {
    if (!state.selected) return;
    try {
      const blob = await (await fetch(state.selected.data)).blob();
      const file = new File([blob], 'prime.jpg', { type: 'image/jpeg' });
      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        await navigator.share({ files: [file], title: 'PRIME' });
      } else {
        downloadPhoto();
      }
    } catch (_) { downloadPhoto(); }
  }

  function setProfile(p) {
    state.profile = p;
    if (p) localStorage.setItem(LS.profile, JSON.stringify(p));
    const logged = !!(p && p.is_login);
    $('accountName').textContent = logged ? (p.username || p.phone_num || 'PRIME 用户') : '未登录';
    $('accountSub').textContent = logged ? (p.is_vip ? `Pro · 至 ${String(p.vip_expire_at).slice(0, 10)}` : `免费 AI ${p.remaining_free_count ?? 5} 次`) : '登录后同步 Pro 与 AI 次数';
    $('loginBtn').textContent = logged ? '退出' : '登录';
    $('proStatus').textContent = logged ? (p.is_vip ? 'Pro 已激活 · 不限次 AI' : `未开通 · 免费 AI ${p.remaining_free_count ?? 5} 次`) : '未开通 · 可先登录再兑换';
  }
  async function loadProfile() {
    if (!state.token) {
      const cached = localStorage.getItem(LS.profile);
      if (cached) { try { setProfile(JSON.parse(cached)); } catch (_) {} }
      return;
    }
    try {
      const res = await fetch(`${API}/ai_camera/auth/me`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${state.token}`, 'Content-Type': 'application/json' },
        body: '{}',
      });
      const body = await res.json();
      if (body.code === 0) setProfile(body.data);
      else { state.token = ''; localStorage.removeItem(LS.token); setProfile(null); }
    } catch (_) {}
  }
  async function sendCode() {
    const phone = $('loginPhone').value.trim();
    if (phone.length < 6) { $('loginHint').textContent = '请输入正确的手机号'; return; }
    try {
      const res = await fetch(`${API}/ai_camera/auth/get_code`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phone_num: phone, scene: 'login' }),
      });
      const body = await res.json();
      if (body.code === 0) {
        const dev = body.data && body.data.dev_code;
        $('loginHint').textContent = dev ? `开发验证码：${dev}` : '验证码已发送，请查看短信';
      } else $('loginHint').textContent = body.message || '发送失败';
    } catch (_) { $('loginHint').textContent = '服务未连通；离线预览可输入 123456'; }
  }
  async function doLogin() {
    const phone = $('loginPhone').value.trim();
    const code = $('loginCode').value.trim();
    if (!phone || !code) { $('loginHint').textContent = '请输入手机号和验证码'; return; }
    try {
      const res = await fetch(`${API}/ai_camera/auth/login`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phone_num: phone, msg_code: code }),
      });
      const body = await res.json();
      if (body.code !== 0) throw new Error(body.message || '登录失败');
      state.token = body.data.token;
      localStorage.setItem(LS.token, state.token);
      setProfile({ ...body.data, is_login: true });
      await loadProfile();
      closeSheets();
      showToast('已登录 PRIME');
    } catch (err) {
      if (code === '123456') {
        state.token = '';
        setProfile({ is_login: true, username: `本地 ${phone.slice(-4)}`, phone_num: phone, is_vip: false, remaining_free_count: 5 });
        closeSheets(); showToast('离线预览登录 · 不同步 Pro');
      } else {
        $('loginHint').textContent = err.message || '登录失败';
      }
    }
  }
  async function loadProducts() {
    try {
      const res = await fetch(`${API}/ai_camera/vip/products`);
      const body = await res.json();
      const products = (body.data && body.data.products) || [];
      $('productList').innerHTML = products.map((p) => `<div class="product"><div><b>${p.title}</b><small>${p.duration_days} 天 · ${p.daily_price}/天</small></div><div style="text-align:right"><div class="price">${p.currency_symbol}${p.actual_price}</div><button data-buy="${p.product_id}">演示开通</button></div></div>`).join('');
    } catch (_) {
      $('productList').innerHTML = '<div class="sheet-note">套餐服务未连通；可先用兑换码 PRIME2026。</div>';
    }
  }
  async function buy(productId) {
    if (!state.token) { openSheet('loginSheet'); return; }
    try {
      const res = await fetch(`${API}/ai_camera/pay/create_order`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${state.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ product_id: productId }),
      });
      const body = await res.json();
      if (body.code !== 0) throw new Error(body.message || '下单失败');
      const no = body.data.out_trade_no;
      const confirm = await fetch(`${API}/ai_camera/pay/mock_confirm?out_trade_no=${encodeURIComponent(no)}`, {
        method: 'POST', headers: { Authorization: `Bearer ${state.token}` },
      });
      const cbody = await confirm.json();
      if (cbody.code !== 0) throw new Error(cbody.message || '确认失败');
      setProfile(cbody.data);
      closeSheets();
      showToast('Pro 已开通（演示）');
    } catch (err) { showToast(err.message || '开通失败'); }
  }
  async function redeem() {
    const code = $('redeemCode').value.trim().toUpperCase();
    if (!code) return;
    if (!state.token) { openSheet('loginSheet'); return; }
    try {
      const res = await fetch(`${API}/api/v1/redeem_vip_code`, {
        method: 'POST', headers: { Authorization: `Bearer ${state.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ redeem_code: code }),
      });
      const body = await res.json();
      if (body.code !== 0) throw new Error(body.message || '兑换失败');
      setProfile(body.data.profile);
      closeSheets();
      showToast('兑换成功');
    } catch (err) { $('redeemHint').textContent = err.message || '兑换失败'; }
  }

  function openSheet(id) {
    closeSheets();
    $('sheetMask').classList.add('show');
    $(id).classList.add('show');
    if (id === 'filterSheet') renderFilterSheet();
    if (id === 'proSheet') loadProducts();
    $('loginApiBase').textContent = API.replace(/^https?:\/\//, '');
  }
  function closeSheets() {
    document.querySelectorAll('.sheet.show').forEach((s) => s.classList.remove('show'));
    $('sheetMask').classList.remove('show');
  }
  function setView(view) {
    document.querySelectorAll('.view').forEach((v) => v.classList.toggle('active', v.id === `view-${view}`));
    document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.view === view));
    if (view === 'gallery') renderGallery();
    if (view === 'mine') loadProfile();
  }

  function bind() {
    $('shutterBtn').addEventListener('click', capture);
    $('aiBtn').addEventListener('click', () => scanAi(false));
    $('autoAiBtn').addEventListener('click', () => {
      state.autoAi = !state.autoAi;
      state.settings.autoAi = state.autoAi;
      saveSettings();
      showToast(state.autoAi ? 'AI 自动构图已开启' : 'AI 自动构图已关闭');
    });
    $('flipBtn').addEventListener('click', () => initCamera(state.facing === 'environment' ? 'user' : 'environment'));
    $('uploadBtn').addEventListener('click', () => $('uploadInput').click());
    $('uploadInput').addEventListener('change', (e) => {
      const file = e.target.files && e.target.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => {
        const img = new Image();
        img.onload = () => {
          state.imported = img;
          if (state.stream) state.stream.getTracks().forEach((t) => t.stop());
          state.stream = null;
          $('video').srcObject = null;
          $('fallback').style.display = 'block';
          $('fallback').style.backgroundImage = `url(${reader.result})`;
          $('cameraState').textContent = '已导入照片 · 可 AI 构图';
        };
        img.src = reader.result;
      };
      reader.readAsDataURL(file);
      e.target.value = '';
    });
    $('settingsBtn').addEventListener('click', () => openSheet('settingsSheet'));
    $('settingsRow').addEventListener('click', () => openSheet('settingsSheet'));
    $('filterBtn').addEventListener('click', () => openSheet('filterSheet'));
    $('loginBtn').addEventListener('click', () => {
      if (state.token) {
        state.token = ''; localStorage.removeItem(LS.token); setProfile(null); showToast('已退出');
      } else openSheet('loginSheet');
    });
    $('buyBtn').addEventListener('click', () => openSheet('proSheet'));
    $('redeemBtn').addEventListener('click', () => openSheet('redeemSheet'));
    $('sendCodeBtn').addEventListener('click', sendCode);
    $('doLoginBtn').addEventListener('click', doLogin);
    $('doRedeemBtn').addEventListener('click', redeem);
    $('guideRow').addEventListener('click', () => showToast('5 步：选拍法 → 放主体 → 等双环 → 按快门 → 编辑'));
    $('aboutRow').addEventListener('click', () => showToast('PRIME v0.4.5 · Doka 1.3.20 全量研究项目'));
    $('toCameraFromEmpty').addEventListener('click', () => setView('camera'));
    $('clearGallery').addEventListener('click', () => {
      if (!state.photos.length) return;
      if (confirm('清空本机相册？')) { state.photos = []; localStorage.removeItem(LS.photos); renderGallery(); }
    });
    $('galleryGrid').addEventListener('click', (e) => {
      const item = e.target.closest('[data-photo]');
      if (item) openPhoto(item.dataset.photo);
    });
    $('photoClose').addEventListener('click', () => { $('photoModal').classList.remove('show'); state.selected = null; });
    $('photoDownload').addEventListener('click', downloadPhoto);
    $('photoShare').addEventListener('click', sharePhoto);
    $('photoDelete').addEventListener('click', () => {
      if (!state.selected) return;
      state.photos = state.photos.filter((p) => p.id !== state.selected.id);
      state.selected = null;
      $('photoModal').classList.remove('show');
      renderGallery();
    });
    $('sheetMask').addEventListener('click', closeSheets);
    document.querySelectorAll('[data-close]').forEach((btn) => btn.addEventListener('click', (e) => { e.preventDefault(); closeSheets(); }));
    document.querySelectorAll('.tab').forEach((tab) => tab.addEventListener('click', () => setView(tab.dataset.view)));
    $('filmStrip').addEventListener('click', (e) => {
      const pill = e.target.closest('[data-filter]');
      if (pill) applyFilter(pill.dataset.filter);
    });
    $('filterCats').addEventListener('click', (e) => {
      const b = e.target.closest('[data-cat]');
      if (b) renderFilterSheet(b.dataset.cat);
    });
    $('filterGrid').addEventListener('click', (e) => {
      const b = e.target.closest('[data-id]');
      if (!b) return;
      const f = filterById(b.dataset.id);
      if (f.pro && !(state.profile && state.profile.is_vip)) { showToast('这是 Pro 胶片；在“我的”兑换 PRIME2026'); return; }
      applyFilter(f.id);
      closeSheets();
    });
    $('productList').addEventListener('click', (e) => {
      const b = e.target.closest('[data-buy]');
      if (b) buy(b.dataset.buy);
    });
    $('setGrid').addEventListener('change', (e) => { state.settings.grid = e.target.checked; saveSettings(); });
    $('setMirror').addEventListener('change', (e) => { state.settings.mirror = e.target.checked; saveSettings(); });
    $('setWatermark').addEventListener('change', (e) => { state.settings.watermark = e.target.checked; saveSettings(); });
    $('setAutoAi').addEventListener('change', (e) => { state.autoAi = e.target.checked; state.settings.autoAi = state.autoAi; saveSettings(); });
    $('setScene').addEventListener('change', (e) => { state.scene = e.target.value; state.settings.scene = state.scene; saveSettings(); });
    window.addEventListener('hashchange', () => {
      if (location.hash === '#mine') setView('mine');
    });
}

  // 初始化
  try { state.photos = JSON.parse(localStorage.getItem(LS.photos) || '[]') || []; } catch (_) { state.photos = []; }
  loadSettings();
  applyFilter(state.filter);
  renderGallery();
  bind();
  if (location.hash === '#mine') setView('mine');
  initCamera();
  loadProfile();
})();
