(function() {
  var langSelect = document.getElementById('custom-lang-select');
  if (!langSelect) return;

  var defaultLang = langSelect.getAttribute('data-default-lang') || 'de';
  var curLang = localStorage.getItem('ga_lang') || defaultLang;
  if (Array.prototype.some.call(langSelect.options, function(o) { return o.value === curLang; })) {
    langSelect.value = curLang;
  }

  var csrfToken = '';
  function ensureToken() {
    if (csrfToken) return Promise.resolve(csrfToken);
    return fetch('/gen-lang.php?action=token', { cache: 'no-store', credentials: 'same-origin' })
      .then(function(r) { return r.json().then(function(d) { return { status: r.status, data: d }; }); })
      .then(function(res) {
        if (res.status === 200 && res.data && res.data.ok && res.data.csrf_token) {
          csrfToken = res.data.csrf_token;
          return csrfToken;
        }
        var err = new Error((res.data && res.data.error) || ('HTTP ' + res.status));
        err.status = res.status;
        throw err;
      });
  }

  function showOverlayError(overlay, bar, sub, err) {
    if (bar) {
      bar.style.width = '100%';
      bar.style.background = '#f85149';
    }
    if (!sub) return;

    var msg = (err && err.message) ? err.message : 'Request failed';
    var isAuthError = (err && err.status === 401) || /session/i.test(msg);

    sub.innerHTML = '';
    var text = document.createElement('div');
    text.style.color = '#ffa198';
    text.style.marginTop = '4px';
    text.textContent = isAuthError
      ? 'Bitte zuerst im KeyHelp-Panel einloggen, um die Sprache zu wechseln.'
      : ('Fehler: ' + msg);
    sub.appendChild(text);

    var closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.textContent = 'Schließen';
    closeBtn.style.cssText = 'margin-top:12px;padding:5px 14px;border-radius:6px;border:1px solid #30363d;background:#21262d;color:#c9d1d9;font-size:12px;cursor:pointer;';
    closeBtn.onclick = function() {
      if (overlay) overlay.style.display = 'none';
      if (bar) {
        bar.style.background = '';
        bar.style.width = '0%';
      }
    };
    sub.appendChild(closeBtn);
  }

  langSelect.addEventListener('change', function() {
    var targetLang = langSelect.value;
    localStorage.setItem('ga_lang', targetLang);

    var overlay = document.getElementById('custom-gen-overlay');
    var bar = document.getElementById('custom-gen-ring');
    var sub = document.getElementById('custom-gen-status');
    var currentFile = window.location.pathname.split('/').pop() || 'index.html';
    var baseDomain = currentFile.replace(/\.[a-z]{2}\.html$/i, '').replace(/\.html$/i, '');
    var targetFile = baseDomain + '.html';

    var oldBar = document.getElementById('custom-gen-bar'); if (oldBar) oldBar.style.display = 'none';
    if (overlay) overlay.style.display = 'flex';
    if (bar) bar.style.stroke = '#1f6feb';
    var pct = 0;
    var mb = 0;
    var done = 0;
    var total = 12;
    if (typeof updateGenRing === 'function') updateGenRing(pct, mb, done, total);
    if (sub) sub.textContent = 'Generating all ' + targetLang.toUpperCase() + ' reports...';

    var timer = setInterval(function() {
      fetch('/gen-lang.php?action=status', { cache: 'no-store', credentials: 'same-origin' })
        .then(function(r) { return r.ok ? r.json() : null; })
        .then(function(st) {
          if (!st || st.ok === false) return;
          total = Number(st.total || total || 12);
          done = Number(st.done || 0);
          mb = Number(st.mb || 0);
          pct = Number(st.pct || 0);
          if (typeof updateGenRing === 'function') updateGenRing(pct, mb, done, total);
          if (sub && st.domain) sub.textContent = (typeof gaMsg === 'function' ? gaMsg('processing', '').replace(/\.\.\.$/, '') : 'Verarbeite ') + st.domain + '...';
          if (pct >= 100 && st.running === false && !window.__gaReloadScheduled) {
            window.__gaReloadScheduled = true;
            clearInterval(timer);
            if (typeof updateGenRing === 'function') updateGenRing(100, mb, total, total);
            if (sub) sub.textContent = gaMsg('done');
            var dir = window.location.pathname.replace(/[^/]*$/, '');
            setTimeout(function() {
              window.location.href = dir + targetFile + '?t=' + Date.now();
            }, 3000);
          }
        })
        .catch(function() {});
    }, 300);

    ensureToken()
      .then(function(tok) {
        return fetch('/gen-lang.php?lang=' + encodeURIComponent(targetLang) + '&domain=' + encodeURIComponent(baseDomain), {
          method: 'POST',
          cache: 'no-store',
          credentials: 'same-origin',
          headers: { 'X-CSRF-Token': tok }
        });
      })
      .then(function(r) { return r.json().then(function(d) { return { status: r.status, data: d }; }); })
      .then(function(res) {
        if (res.status === 200 && res.data && res.data.ok) {
          if (res.data.csrf_token) csrfToken = res.data.csrf_token;
          setTimeout(function() {
            if (!window.__gaReloadScheduled) {
              window.__gaReloadScheduled = true;
              clearInterval(timer);
              if (sub) sub.textContent = gaMsg('done');
              if (typeof updateGenRing === 'function') updateGenRing(100, mb, total, total);
              var dir = window.location.pathname.replace(/[^/]*$/, '');
              setTimeout(function() {
                window.location.href = dir + targetFile + '?t=' + Date.now();
              }, 3000);
            }
          }, 1500);
        } else {
          var err = new Error((res.data && res.data.error) || ('HTTP ' + res.status));
          err.status = res.status;
          showOverlayError(overlay, bar, sub, err);
        }
      })
      .catch(function(err) {
        clearInterval(timer);
        showOverlayError(overlay, bar, sub, err);
      });
  });
})();


(function attachGoAccessLogModal() {
  function isDe() {
    var l = (window.__gaTargetLang || '').toLowerCase();
    if (!l) {
      var sel = document.getElementById('custom-lang-select');
      if (sel && sel.value) l = String(sel.value).toLowerCase();
    }
    if (!l) {
      var nav = (navigator.language || '').toLowerCase();
      return nav.indexOf('de') === 0;
    }
    return l === 'de';
  }

  function ensureModal() {
    var modal = document.getElementById('custom-log-modal');
    if (modal) return modal;
    modal = document.createElement('div');
    modal.id = 'custom-log-modal';
    modal.style.cssText = 'display:none;position:fixed;inset:0;z-index:2147483647;background:rgba(5,8,14,0.82);backdrop-filter:blur(4px);align-items:center;justify-content:center;padding:20px;';
    modal.innerHTML =
      '<div style="width:min(920px,96vw);max-height:84vh;display:flex;flex-direction:column;background:#121824;border:1px solid #232d42;border-radius:12px;box-shadow:0 24px 64px rgba(0,0,0,0.7);overflow:hidden;">' +
        '<div style="display:flex;align-items:center;justify-content:space-between;gap:12px;padding:12px 16px;border-bottom:1px solid #232d42;background:#0e131d;">' +
          '<div>' +
            '<div id="custom-log-title" style="font-size:14px;font-weight:600;color:#e6edf3;"></div>' +
            '<div id="custom-log-source" style="font-size:11.5px;color:#8b949e;margin-top:2px;"></div>' +
          '</div>' +
          '<div style="display:flex;align-items:center;gap:8px;">' +
            '<button type="button" id="custom-log-refresh" style="padding:6px 10px;border-radius:7px;background:#1b2538;border:1px solid #2c3b57;color:#dbeafe;font-size:12px;font-weight:600;cursor:pointer;"></button>' +
            '<button type="button" id="custom-log-close" style="padding:6px 10px;border-radius:7px;background:#261820;border:1px solid #522836;color:#fca5a5;font-size:12px;font-weight:600;cursor:pointer;"></button>' +
          '</div>' +
        '</div>' +
        '<pre id="custom-log-pre" style="margin:0;padding:14px 16px;min-height:240px;overflow:auto;flex:1;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;font-size:12px;line-height:1.45;color:#d6dee8;background:#090d14;white-space:pre-wrap;word-break:break-word;"></pre>' +
      '</div>';
    document.body.appendChild(modal);

    modal.addEventListener('click', function(ev) {
      if (ev.target === modal) modal.style.display = 'none';
    });
    document.getElementById('custom-log-close').addEventListener('click', function() {
      modal.style.display = 'none';
    });
    document.getElementById('custom-log-refresh').addEventListener('click', function() {
      loadLog();
    });
    document.addEventListener('keydown', function(ev) {
      if (ev.key === 'Escape' && modal.style.display === 'flex') modal.style.display = 'none';
    });
    return modal;
  }

  function loadLog() {
    var de = isDe();
    var titleEl = document.getElementById('custom-log-title');
    var refreshBtn = document.getElementById('custom-log-refresh');
    var closeBtn = document.getElementById('custom-log-close');
    var sourceEl = document.getElementById('custom-log-source');
    var preEl = document.getElementById('custom-log-pre');
    if (titleEl) titleEl.textContent = de ? 'Log-Ansicht (letzte 200 Zeilen)' : 'Log Viewer (last 200 lines)';
    if (refreshBtn) refreshBtn.textContent = de ? 'Aktualisieren' : 'Refresh';
    if (closeBtn) closeBtn.textContent = de ? 'Schließen' : 'Close';
    if (preEl) preEl.textContent = de ? 'Lade Log...' : 'Loading log...';

    fetch('log-view.php?t=' + Date.now(), { cache: 'no-store' })
      .then(function(res) { return res.json().then(function(d) { return { ok: res.ok, status: res.status, data: d }; }); })
      .then(function(info) {
        if (!info.ok || !info.data || info.data.ok === false) {
          if (preEl) preEl.textContent = (info.data && info.data.error) ? info.data.error : ('HTTP ' + info.status);
          return;
        }
        if (sourceEl) sourceEl.textContent = info.data.source || '';
        if (preEl) {
          preEl.textContent = info.data.content || '';
          preEl.scrollTop = preEl.scrollHeight;
        }
      })
      .catch(function(err) {
        if (preEl) preEl.textContent = String(err);
      });
  }

  document.addEventListener('click', function(e) {
    var btn = e.target && e.target.closest ? e.target.closest('#custom-log-btn') : null;
    if (!btn) return;
    e.preventDefault();
    e.stopPropagation();
    var modal = ensureModal();
    modal.style.display = 'flex';
    loadLog();
  }, true);
})();

(function initVersionCheck() {
  const box = document.getElementById('custom-version-box');
  if (!box) return;

  const isGerman = (navigator.language || '').toLowerCase().startsWith('de');
  const currentVer = (box.getAttribute('data-current-version') || '1.0.0').trim();
  const repoUrl = 'https://github.com/NicoMSH-plugins/KeyHelp-GoAccess-Multi-Language';
  const rawUrl = 'https://raw.githubusercontent.com/NicoMSH-plugins/KeyHelp-GoAccess-Multi-Language/main/VERSION';
  const cacheKey = 'ga_git_version_cache_v1';
  const ttlMs = 5 * 60 * 1000;

  function parseVer(v) {
    return String(v || '0.0.0')
      .replace(/^v/i, '')
      .split('.')
      .map(n => parseInt(n, 10) || 0);
  }

  function isNewer(remoteVer, localVer) {
    const a = parseVer(remoteVer);
    const b = parseVer(localVer);
    const len = Math.max(a.length, b.length);
    for (let i = 0; i < len; i++) {
      const x = a[i] || 0;
      const y = b[i] || 0;
      if (x > y) return true;
      if (x < y) return false;
    }
    return false;
  }

function waitForRunnerFinish(sub, maxWaitMs) {
    const limit = maxWaitMs || 180000;
    const startedAt = Date.now();
    let sawRunning = false;

    return new Promise((resolve) => {
      function check() {
        fetch('/gen-lang.php?action=status', { cache: 'no-store', credentials: 'same-origin' })
          .then(r => (r.ok ? r.json() : null))
          .then(st => {
            if (st && st.ok !== false) {
              const pct = Number(st.pct || 0);
              const mb = Number(st.mb || 0);
              const done = Number(st.done || 0);
              const total = Number(st.total || 1);
              if (st.running === true || pct < 100) sawRunning = true;
              if (typeof updateGenRing === 'function') {
                updateGenRing(pct, mb, done, total || 1);
              }
              if (sub && st.domain) {
                sub.textContent = String(st.domain);
              }
              const elapsed = Date.now() - startedAt;
              if (st.running === false && pct >= 100 && (sawRunning || elapsed >= 1200)) {
                if (typeof updateGenRing === 'function') updateGenRing(100, mb, total || 1, total || 1);
                resolve();
                return;
              }
            }
            if ((Date.now() - startedAt) >= limit) {
              resolve();
              return;
            }
            setTimeout(check, 600);
          })
          .catch(() => {
            if ((Date.now() - startedAt) >= limit) {
              resolve();
              return;
            }
            setTimeout(check, 1000);
          });
      }
      setTimeout(check, 500);
    });
  }

  function triggerSelfUpdate(btn, targetVer) {
    if (!btn || btn.dataset.busy === '1') return;
    btn.dataset.busy = '1';
    btn.disabled = true;
    const origText = btn.textContent;
    btn.textContent = isGerman ? 'Update läuft...' : 'Updating...';

    const overlay = document.getElementById('custom-gen-overlay');
    const bar = document.getElementById('custom-gen-ring');
    const sub = document.getElementById('custom-gen-status');
    const oldBar = document.getElementById('custom-gen-bar');
    if (oldBar) oldBar.style.display = 'none';
    if (overlay) {
      overlay.classList.add('active');
      overlay.style.display = 'flex';
    }
    if (bar) bar.style.stroke = '#1f6feb';
    if (typeof updateGenRing === 'function') updateGenRing(5, 0, 0, 1);
    if (sub) sub.textContent = isGerman ? 'Starte Update auf v' + targetVer + '...' : 'Starting update to v' + targetVer + '...';

    fetch('/gen-lang.php?action=token', { credentials: 'same-origin' })
      .then(r => r.json())
      .then(tok => {
        const headers = { 'X-Requested-With': 'XMLHttpRequest' };
        if (tok && tok.csrf_token) headers['X-CSRF-Token'] = tok.csrf_token;
        return fetch('/gen-lang.php?action=update', {
          method: 'POST',
          credentials: 'same-origin',
          headers
        });
      })
      .then(r => r.json())
      .then(res => {
        if (res && res.ok) {
          try { localStorage.removeItem(cacheKey); } catch (_) {}
          waitForRunnerFinish(sub, 180000).then(() => {
            if (sub) sub.textContent = isGerman ? 'Fertig! Lade neu...' : 'Done! Reloading...';
            setTimeout(() => {
              const currentFile = window.location.pathname.split('/').pop() || 'index.html';
              const dir = window.location.pathname.replace(/[^/]*$/, '');
              window.location.href = dir + currentFile + '?t=' + Date.now();
            }, 800);
          });
        } else {
          throw new Error((res && res.error) || 'Update failed');
        }
      })
      .catch(err => {
        if (overlay) {
          overlay.classList.remove('active');
          overlay.style.display = 'none';
        }
        btn.disabled = false;
        btn.dataset.busy = '0';
        btn.textContent = origText;
        alert((isGerman ? 'Update fehlgeschlagen: ' : 'Update failed: ') + err.message);
      });
  }

  function renderVersion(remoteVer) {
    const cleanRemote = String(remoteVer || '').trim().replace(/^v/i, '');
    if (cleanRemote && isNewer(cleanRemote, currentVer)) {
      const btnText = isGerman
        ? `Update auf v${cleanRemote}`
        : `Update to v${cleanRemote}`;
      box.innerHTML = `<div style="margin-bottom:4px;">v${currentVer} &rarr; v${cleanRemote}</div><button type="button" id="custom-update-btn" style="display:flex;align-items:center;justify-content:center;gap:6px;width:100%;padding:7px 10px;border-radius:8px;background:rgba(56,189,248,0.16);border:1px solid rgba(56,189,248,0.45);color:#7dd3fc;font-size:12px;font-weight:600;cursor:pointer;">${btnText}</button>`;
      const updBtn = document.getElementById('custom-update-btn');
      if (updBtn) updBtn.addEventListener('click', () => triggerSelfUpdate(updBtn, cleanRemote));
    } else {
      box.textContent = isGerman ? `v${currentVer} · Aktuell` : `v${currentVer} · Up to date`;
    }
  }

  try {
    const cachedRaw = localStorage.getItem(cacheKey);
    if (cachedRaw) {
      const cached = JSON.parse(cachedRaw);
      if (cached && cached.ts && (Date.now() - cached.ts) < ttlMs && cached.ver) {
        renderVersion(cached.ver);
        return;
      }
    }
  } catch (_) {}

  fetch(rawUrl, { cache: 'no-store' })
    .then(r => r.ok ? r.text() : Promise.reject(new Error('HTTP ' + r.status)))
    .then(txt => {
      const ver = txt.trim().replace(/^v/i, '');
      if (!ver) return;
      try {
        localStorage.setItem(cacheKey, JSON.stringify({ ts: Date.now(), ver }));
      } catch (_) {}
      renderVersion(ver);
    })
    .catch(() => {
      box.textContent = `v${currentVer}`;
    });
})();
