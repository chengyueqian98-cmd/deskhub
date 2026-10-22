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

  fetch('https://api.github.com/repos/chengyueqian98-cmd/deskhub/releases/latest')
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
})();
