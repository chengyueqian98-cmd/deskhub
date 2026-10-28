// 语言切换；按系统把对应的下载按钮放前面；从 GitHub 拿最新版本的安装包直链（拿不到就留着跳到 Releases 页）
(function () {
  var root = document.documentElement;
  document.getElementById('lang').addEventListener('click', function () {
    var next = root.lang === 'en' ? 'zh-CN' : 'en';
    root.lang = next;
    try { localStorage.setItem('lang', next); } catch (e) {}
  });

  // Windows 用户：Windows 按钮当主按钮、放前面
  var isWin = /Windows/i.test(navigator.userAgent);
  if (isWin) {
    var cta = document.getElementById('cta');
    var mac = cta.querySelector('[data-dl="mac"]'), win = cta.querySelector('[data-dl="win"]');
    cta.insertBefore(win, mac);
    win.className = 'btn primary'; mac.className = 'btn ghost';
  }

  fetch('https://api.github.com/repos/chengyueqian98-cmd/glancedesk/releases/latest')
    .then(function (r) { return r.ok ? r.json() : null; })
    .then(function (rel) {
      if (!rel) return;
      var assets = rel.assets || [];
      var find = function (re) { var a = assets.find(function (x) { return re.test(x.name); }); return a && a.browser_download_url; };
      var urls = { mac: find(/\.dmg$/i), win: find(/Windows.*Setup\.exe$/i) };
      document.querySelectorAll('[data-dl]').forEach(function (a) {
        var u = urls[a.getAttribute('data-dl')];
        if (u) { a.href = u; return; }
        if (a.getAttribute('data-dl') === 'win') {
          // 这一版还没有 Windows 安装包
          a.className = 'btn soon';
          a.removeAttribute('href');
          a.innerHTML = '<span data-zh>Windows 版即将推出</span><span data-en>Windows coming soon</span>';
        }
      });
      var v = (rel.tag_name || '').replace(/^v/, '');
      if (v) document.getElementById('ver').textContent = '· v' + v;
    })
    .catch(function () {});

  // 往下滚时卡片浮上来
  var reveal = document.querySelectorAll('section .card, section .split, .widgets, #demo .demo');
  if ('IntersectionObserver' in window) {
    var ro = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); ro.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -8% 0px' });
    reveal.forEach(function (el) { el.classList.add('reveal'); ro.observe(el); });
  }

  demo();
})();

// —— 演示动画：一个时间轴循环播放；滚出屏幕就暂停，减少动态效果时停在「浮层+回答」那一帧 ——
function demo() {
  var box = document.getElementById('demo-stage');
  if (!box) return;
  var stage = box.firstElementChild;
  var cursor = document.getElementById('demo-cursor');
  var keys = document.getElementById('demo-keys');
  var ask = document.getElementById('demo-ask');
  var q = document.getElementById('demo-q'), qq = document.getElementById('demo-qq'), a = document.getElementById('demo-a');
  var steps = document.querySelectorAll('#demo-steps li');
  var text = function () {
    var en = document.documentElement.lang === 'en';
    return en
      ? { q: "What's on today?", a: 'Design review in 15 minutes, lunch with Lin at 12:30, gym at 6. Rain this afternoon, so bring an umbrella.' }
      : { q: '我今天有什么事？', a: '15 分钟后有设计评审，12:30 和小林吃午饭，晚上 6 点健身。下午有雨，记得带伞。' };
  };

  var fit = function () { stage.style.setProperty('--s', box.clientWidth / 960); };
  fit();
  window.addEventListener('resize', fit);

  var timers = [], playing = false;
  var at = function (ms, fn) { timers.push(setTimeout(fn, ms)); };
  var step = function (i) { steps.forEach(function (li, j) { li.classList.toggle('on', j === i); }); };
  var key = function (k, down) { var el = keys.querySelector('[data-k="' + k + '"]'); if (el) el.classList.toggle('down', down); };
  var press = function (t0, k) { at(t0, function () { key(k, true); }); at(t0 + 220, function () { key(k, false); }); };
  var moveTo = function (el, dx, dy) {
    var s = box.clientWidth / 960, r = el.getBoundingClientRect(), b = box.getBoundingClientRect();
    cursor.style.left = ((r.left - b.left) / s + dx) + 'px';
    cursor.style.top = ((r.top - b.top) / s + dy) + 'px';
  };
  var type = function (el, str, t0, gap) {
    for (var i = 1; i <= str.length; i++) (function (n) { at(t0 + n * gap, function () { el.textContent = str.slice(0, n); }); })(i);
    return t0 + str.length * gap;
  };

  var reset = function () {
    stage.className = 'stage';
    keys.className = 'keys';
    ask.className = 'ask';
    q.textContent = qq.textContent = a.textContent = '';
    cursor.setAttribute('class', 'cursor');   // SVG 不能直接赋 className
    cursor.style.left = '560px'; cursor.style.top = '470px';
  };

  var still = function () {
    var t = text();
    reset();
    stage.classList.add('clean', 'over', 'asked');
    cursor.classList.add('gone');
    q.textContent = t.q; qq.textContent = t.q; a.textContent = t.a;
    ask.classList.add('typing');
    step(2);
  };

  var run = function () {
    var t = text();
    reset();
    step(0);
    // ① 光标走到开关，点一下，图标收起
    at(600, function () { moveTo(stage.querySelector('.tg'), 14, 6); });
    at(1500, function () { cursor.classList.add('press'); });
    at(1640, function () { cursor.classList.remove('press'); stage.classList.add('clean'); });
    // ② 按 ⌃⌥空格
    at(3000, function () { step(1); cursor.classList.add('gone'); stage.classList.add('keys-up'); });
    press(3500, 'ctrl'); press(3750, 'opt'); press(4000, 'space');
    at(4450, function () { stage.classList.remove('keys-up'); stage.classList.add('over'); });
    // ③ 打字提问，回答一个字一个字出来
    at(5200, function () { step(2); ask.classList.add('typing'); });
    var t1 = type(q, t.q, 5300, 110);
    at(t1 + 400, function () { qq.textContent = t.q; stage.classList.add('asked'); });
    var t2 = type(a, t.a, t1 + 600, 38);
    // ④ Esc 收起
    var t3 = t2 + 2600;
    at(t3, function () { step(3); keys.classList.add('esc'); stage.classList.add('keys-up'); });
    press(t3 + 500, 'esc');
    at(t3 + 750, function () { stage.classList.remove('over', 'asked'); ask.classList.remove('typing'); });
    at(t3 + 1300, function () { stage.classList.remove('keys-up'); });
    // 图标回来，从头再播
    at(t3 + 3200, function () { stage.classList.remove('clean'); });
    at(t3 + 4200, function () { if (playing) run(); });
  };

  var stop = function () { playing = false; timers.forEach(clearTimeout); timers = []; };
  var start = function () { if (playing) return; playing = true; run(); };

  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches || !('IntersectionObserver' in window)) { still(); return; }
  still();
  new IntersectionObserver(function (es) { es[0].isIntersecting ? start() : stop(); }, { threshold: 0.35 }).observe(box);
  // 切换语言后从头播，文字跟着换
  document.getElementById('lang').addEventListener('click', function () { if (playing) { stop(); start(); } else still(); });
}
