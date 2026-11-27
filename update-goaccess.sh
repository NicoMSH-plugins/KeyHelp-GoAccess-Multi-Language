#!/bin/bash
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_CYAN=$'\033[0;36m'
C_BCYAN=$'\033[1;36m'
C_GREEN=$'\033[0;32m'
C_RED=$'\033[0;31m'
C_ORANGE=$'\033[38;5;208m'
C_GRAY=$'\033[0;90m'
C_YELLOW=$'\033[0;33m'

LOG_FILE="/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/goaccess-update.log"
[ -d "$(dirname "$LOG_FILE")" ] || LOG_FILE="/var/log/goaccess-update.log"
: > "$LOG_FILE"
chown keyhelp:keyhelp "$LOG_FILE" 2>/dev/null || true
chmod 664 "$LOG_FILE" 2>/dev/null || true
log_msg() { printf "[%s] %s\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$1" >> "$LOG_FILE"; }
log_msg "=== Start GoAccess Update ==="
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_VERSION="1.0.0"
for _vf in "${SCRIPT_DIR}/VERSION" /usr/local/bin/VERSION /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/VERSION; do [ -f "$_vf" ] && { APP_VERSION="$(tr -d '[:space:]' < "$_vf")"; break; }; done
[ -z "${APP_VERSION}" ] && APP_VERSION="1.0.0"
REPO_GA="/home/keyhelp/www/keyhelp/dashboard-layout/goaccess"
[ -f "$SCRIPT_DIR/assets/dashboard-inject.js" ] && REPO_GA="$SCRIPT_DIR"

GLOBAL_STATE_DIR="/var/lib/goaccess-db"
LANG_STATE_FILE="${GLOBAL_STATE_DIR}/.current_lang"
mkdir -p "$GLOBAL_STATE_DIR"

exec 9>"${GLOBAL_STATE_DIR}/.update.lock"
flock -n 9 || { echo "Ein update-goaccess.sh Lauf ist bereits aktiv – breche ab."; exit 0; }

if [ -z "$TARGET_LANG" ] && [ -f "$LANG_STATE_FILE" ]; then
  TARGET_LANG=$(tr -cd 'a-z' < "$LANG_STATE_FILE" | head -c 2)
fi
TARGET_LANG="${TARGET_LANG:-${LANG_MODE:-de}}"
printf '%s' "$TARGET_LANG" > "$LANG_STATE_FILE"

case "$TARGET_LANG" in
  de) ACTIVE_LOCALE="de_DE.UTF-8"; ACTIVE_LANG="de" ;;
  en) ACTIVE_LOCALE="en_US.UTF-8"; ACTIVE_LANG="en" ;;
  es) ACTIVE_LOCALE="es_ES.UTF-8"; ACTIVE_LANG="es" ;;
  fr) ACTIVE_LOCALE="fr_FR.UTF-8"; ACTIVE_LANG="fr" ;;
  it) ACTIVE_LOCALE="it_IT.UTF-8"; ACTIVE_LANG="it" ;;
  ja) ACTIVE_LOCALE="ja_JP.UTF-8"; ACTIVE_LANG="ja" ;;
  ko) ACTIVE_LOCALE="ko_KR.UTF-8"; ACTIVE_LANG="ko" ;;
  pt) ACTIVE_LOCALE="pt_BR.UTF-8"; ACTIVE_LANG="pt_BR" ;;
  ru) ACTIVE_LOCALE="ru_RU.UTF-8"; ACTIVE_LANG="ru" ;;
  sv) ACTIVE_LOCALE="sv_SE.UTF-8"; ACTIVE_LANG="sv" ;;
  uk) ACTIVE_LOCALE="uk_UA.UTF-8"; ACTIVE_LANG="uk" ;;
  zh) ACTIVE_LOCALE="zh_CN.UTF-8"; ACTIVE_LANG="zh_CN" ;;
  *)  ACTIVE_LOCALE="de_DE.UTF-8"; ACTIVE_LANG="de" ;;
esac

export LC_ALL="$ACTIVE_LOCALE"
export LANG="$ACTIVE_LOCALE"
export LANGUAGE="$ACTIVE_LANG"

echo "Sprache: ${TARGET_LANG} (${ACTIVE_LOCALE})"

GEOIP_OPT=""
MMDB=$(find /usr/share /var/lib -name "*.mmdb" 2>/dev/null | head -n 1)
[ -n "$MMDB" ] && GEOIP_OPT="--geoip-database=$MMDB"

AVAIL_LANGS=()
while IFS= read -r loc; do
  case "$loc" in
    de_DE.*) AVAIL_LANGS+=("de") ;;
    en_US.*) AVAIL_LANGS+=("en") ;;
    es_ES.*) AVAIL_LANGS+=("es") ;;
    fr_FR.*) AVAIL_LANGS+=("fr") ;;
    it_IT.*) AVAIL_LANGS+=("it") ;;
    ja_JP.*) AVAIL_LANGS+=("ja") ;;
    ko_KR.*) AVAIL_LANGS+=("ko") ;;
    pt_BR.*) AVAIL_LANGS+=("pt") ;;
    ru_RU.*) AVAIL_LANGS+=("ru") ;;
    sv_SE.*) AVAIL_LANGS+=("sv") ;;
    uk_UA.*) AVAIL_LANGS+=("uk") ;;
    zh_CN.*) AVAIL_LANGS+=("zh") ;;
  esac
done < <(locale -a 2>/dev/null | grep -i '\.utf-\?8$' | sort -u)
[ "${#AVAIL_LANGS[@]}" -eq 0 ] && AVAIL_LANGS=("de" "en")

lang_options_html=""
for lcode in "${AVAIL_LANGS[@]}"; do
  lupper=$(printf '%s' "$lcode" | tr '[:lower:]' '[:upper:]')
  lang_options_html+="<option value=\"${lcode}\">${lupper}</option>"
done

INJECT_JS=""
[ -r "$REPO_GA/assets/dashboard-inject.js" ] && INJECT_JS=$(cat "$REPO_GA/assets/dashboard-inject.js")

shopt -s nullglob
CONF_FILES=("$REPO_GA"/*.conf)
shopt -u nullglob
[ "${#CONF_FILES[@]}" -eq 0 ] && { echo "Keine *.conf Dateien in ${REPO_GA} gefunden."; exit 0; }

for CONF_FILE in "${CONF_FILES[@]}"; do
  KH_USER=""
  STATS_DOMAIN=""
  OUT_DIR=""
  DB_BASE=""
  LOG_BASE=""
  KEYHELP_FMT='%h %^[%d:%t %^] "%r" %s %b "%R" "%u" %^ %^'
  DATE_FMT='%d/%b/%Y'
  TIME_FMT='%H:%M:%S'
  EXCLUDE_DOMAINS=""
  HIDE_NAV_DOMAINS=""
  DEFAULT_LANG="de"

  # shellcheck disable=SC1090
  source "$CONF_FILE"

  [ -z "$KH_USER" ] && continue
  OUT_DIR="${OUT_DIR:-/home/users/${KH_USER}/www/${STATS_DOMAIN}}"
  DB_BASE="${DB_BASE:-/var/lib/goaccess-db/${KH_USER}}"
  LOG_BASE="${LOG_BASE:-/home/users/${KH_USER}/logs}"
  [ -z "$OUT_DIR" ] || [ ! -d "$LOG_BASE" ] && continue

  echo -e "${C_BCYAN}=== Benutzer: ${C_RESET}${C_BOLD}${KH_USER}${C_RESET}${C_DIM} -> ${OUT_DIR}${C_RESET}${C_BCYAN} ===${C_RESET}"
  mkdir -p "$OUT_DIR" "$DB_BASE"

  RAW_DOMAINS=()
  for dir in "$LOG_BASE"/*; do
    [ -d "$dir" ] || continue
    dom=$(basename "$dir")
    [[ " $EXCLUDE_DOMAINS " == *" $dom "* ]] && continue
    if compgen -G "$dir/*access.log*" >/dev/null || compgen -G "$dir/*.log*" >/dev/null; then
      RAW_DOMAINS+=("$dom")
    fi
  done

  _FILTERED_DOMAINS=()
  while IFS= read -r _d; do
    [ -n "$_d" ] || continue
    [[ " $EXCLUDE_DOMAINS " == *" $_d "* ]] && continue
    _FILTERED_DOMAINS+=("$_d")
  done < <(printf '%s\n' "${RAW_DOMAINS[@]}" | LC_ALL=C sort -f)
  DOMAINS=("${_FILTERED_DOMAINS[@]}")
  total_doms="${#DOMAINS[@]}"
  write_gen_progress() {
    local p_pct="${1:-0}"
    local p_dom="${2:-}"
    local p_done="${3:-0}"
    local p_total="${4:-0}"
    local p_running="${5:-true}"
    local p_bytes="${_cum_bytes:-0}"
    local p_mb
    p_mb=$(awk -v b="$p_bytes" 'BEGIN { printf "%.1f", b / 1048576 }')
    printf '{"pct":%s,"mb":%s,"domain":"%s","done":%s,"total":%s,"running":%s}\n' \
      "$p_pct" "$p_mb" "$p_dom" "$p_done" "$p_total" "$p_running" > "${DB_BASE}/.gen_progress"
    chmod 0664 "${DB_BASE}/.gen_progress" 2>/dev/null || true
    cp -f "${DB_BASE}/.gen_progress" "/var/lib/goaccess-db/.gen_progress" 2>/dev/null || true
    chmod 0664 "/var/lib/goaccess-db/.gen_progress" 2>/dev/null || true
  }
  write_gen_progress 0 "" 0 "${total_doms}" true
  echo -e "${C_DIM}Gefundene Domains:${C_RESET} ${C_BOLD}${total_doms}${C_RESET}"

  for html in "$OUT_DIR"/*.html; do
    [ -e "$html" ] || continue
    base=$(basename "$html" .html)
    [ "$base" = "index" ] && continue
    keep=false
    for dom in "${DOMAINS[@]}"; do
      if [ "$dom" = "$base" ] && [[ " $HIDE_NAV_DOMAINS " != *" $dom "* ]]; then
        keep=true
        break
      fi
    done
    [ "$keep" = false ] && rm -f "$html"
  done

  _cum_bytes=0
  idx=0
  for dom in "${DOMAINS[@]}"; do
    idx=$((idx + 1))
    _p_pct=$(( (idx - 1) * 100 / (total_doms > 0 ? total_doms : 1) ))
    log_dir="$LOG_BASE/$dom"
    db_dir="$DB_BASE/$dom"
    db_existed=false
    if [ -d "$db_dir" ] && [ -n "$(ls -A "$db_dir" 2>/dev/null)" ]; then
      db_existed=true
    fi
    mkdir -p "$db_dir"

    mapfile -t _prog_logs < <(ls -1t "$log_dir"/*access.log "$log_dir"/access.log 2>/dev/null | awk '!seen[$0]++')
    if [ "${#_prog_logs[@]}" -eq 0 ]; then
      mapfile -t _prog_logs < <(ls -1t "$log_dir"/*.log 2>/dev/null | grep -v '\.gz$' | awk '!seen[$0]++')
    fi
    _dom_bytes=0
    if [ "${#_prog_logs[@]}" -gt 0 ]; then
      _dom_bytes=$(stat -c '%s' "${_prog_logs[@]}" 2>/dev/null | awk '{s+=$1} END {print s+0}')
    fi

    if [ "${DB_ONLY:-0}" = "1" ]; then
      logs=()
    elif [ "$db_existed" = true ]; then
      logs=("${_prog_logs[@]}")
    else
      mapfile -t logs < <(ls -1t "$log_dir"/*access.log* 2>/dev/null)
      if [ "${#logs[@]}" -eq 0 ]; then
        mapfile -t logs < <(ls -1t "$log_dir"/*.log* 2>/dev/null)
      fi
    fi
    _prev_cum_bytes="${_cum_bytes:-0}"
    _target_cum_bytes=$(( _prev_cum_bytes + ${_dom_bytes:-0} ))
    if [ "${DB_ONLY:-0}" = "1" ]; then
      for _sub_step in 1 2 3 4; do
        _cum_bytes=$(( _prev_cum_bytes + ((_target_cum_bytes - _prev_cum_bytes) * _sub_step / 4) ))
        _sub_pct=$(( ((idx - 1) * 4 + _sub_step) * 100 / ((total_doms > 0 ? total_doms : 1) * 4) ))
        [ "$_sub_pct" -gt 99 ] && _sub_pct=99
        write_gen_progress "${_sub_pct}" "${dom}" "${idx}" "${total_doms}" "true"
        sleep 0.25
      done
      _cum_bytes="$_target_cum_bytes"
    else
      _cum_bytes="$_target_cum_bytes"
      write_gen_progress "${_p_pct}" "${dom}" "${idx}" "${total_doms}" "true"
    fi
    if [ "${DB_ONLY:-0}" != "1" ] && [ "${#logs[@]}" -eq 0 ]; then
      echo "  [${idx}/${total_doms}] ${dom}: keine Logdateien – uebersprungen."
      continue
    fi

    echo -e "${C_BCYAN}[${idx}/${total_doms}]${C_RESET} ${C_BOLD}${C_CYAN}${dom}${C_RESET} ${C_GRAY}(${#logs[@]} Logdateien)${C_RESET}"

    nav_links=""
    for nav_dom in "${DOMAINS[@]}"; do
      [[ " $HIDE_NAV_DOMAINS " == *" $nav_dom "* ]] && continue
      if [ "$nav_dom" = "$dom" ]; then
        nav_links+="<a href=\"./${nav_dom}.html\" class=\"active\">${nav_dom}</a>"
      else
        nav_links+="<a href=\"./${nav_dom}.html\">${nav_dom}</a>"
      fi
    done

    NAV_BAR="<style>
      #custom-domain-sidebar {
        position: fixed;
        top: 0;
        left: 0;
        bottom: 0;
        width: 205px;
        z-index: 100;
        background: #0d1117;
        border-right: 1px solid #30363d;
        padding: 12px 10px;
        display: flex;
        flex-direction: column;
        gap: 8px;
        font-family: system-ui, -apple-system, sans-serif;
        box-sizing: border-box;
      }
      #custom-domain-sidebar .sidebar-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 6px;
        padding: 0 2px;
      }
      #custom-domain-sidebar .sidebar-title {
        color: #8b949e;
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: .06em;
      }
      #custom-lang-select {
        background: #161b22;
        border: 1px solid #30363d;
        border-radius: 5px;
        color: #c9d1d9;
        font-size: 11px;
        padding: 2px 6px;
        outline: none;
        cursor: pointer;
      }
      #custom-lang-select:focus {
        border-color: #58a6ff;
      }
      #custom-domain-search {
        width: 100%;
        padding: 6px 8px;
        border-radius: 6px;
        border: 1px solid #30363d;
        background: #161b22;
        color: #e6edf3;
        font-size: 12px;
        outline: none;
        box-sizing: border-box;
      }
      #custom-domain-search:focus {
        border-color: #58a6ff;
      }
      #custom-domain-list {
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        gap: 3px;
        padding-right: 2px;
      }
      #custom-domain-list a {
        color: #c9d1d9;
        text-decoration: none;
        padding: 5px 8px;
        border-radius: 6px;
        font-size: 12px;
        line-height: 1.35;
        word-break: break-word;
        border: 1px solid transparent;
      }
      #custom-domain-list a:hover {
        background: #161b22;
        border-color: #30363d;
      }
      #custom-domain-list a.active {
        background: #1f6feb;
        color: #ffffff;
        font-weight: 600;
      }

      body {
        margin-left: 0 !important;
      }
      body > .container {
        margin-left: 265px !important;
        width: calc(100% - 265px) !important;
        max-width: none !important;
      }
      body > nav {
        left: 205px !important;
        width: 60px !important;
        z-index: 95 !important;
      }
      body > nav.active {
        left: 205px !important;
        width: 260px !important;
        z-index: 97 !important;
      }
      body > nav:not(.active) .nav-list > * {
        display: none !important;
      }
      nav .nav-bars,
      nav .nav-gears,
      nav .nav-ws-status {
        left: 218px !important;
        z-index: 98 !important;
      }
      body > nav.active .nav-bars {
        left: 218px !important;
        right: auto !important;
        top: 16px !important;
      }
      body > nav.active .nav-gears,
      body > nav.active .nav-ws-status {
        display: none !important;
      }
      body > nav.active header {
        margin-top: 48px !important;
      }
      nav .powered {
        display: none !important;
      }
      @media (max-width: 768px) {
        #custom-domain-sidebar {
          position: static;
          width: 100%;
          bottom: auto;
          max-height: 220px;
          border-right: none;
          border-bottom: 1px solid #30363d;
        }
        body > .container {
          margin-left: 0 !important;
          width: 100% !important;
        }
        body > nav,
        body > nav.active {
          left: 0 !important;
        }
        nav .nav-bars,
        nav .nav-gears,
        nav .nav-ws-status {
          left: 13px !important;
        }
      }
      #custom-gen-overlay {
        display: none;
        position: fixed;
        inset: 0;
        z-index: 99999;
        background: rgba(13, 17, 23, 0.88);
        backdrop-filter: blur(3px);
        color: #e6edf3;
        font-family: system-ui, -apple-system, sans-serif;
        align-items: center;
        justify-content: center;
        flex-direction: column;
        gap: 14px;
      }
      .ga-ring-box {
        position: relative;
        width: 132px;
        height: 132px;
        display: flex;
        align-items: center;
        justify-content: center;
      }
      .ga-ring-svg {
        width: 132px;
        height: 132px;
        transform: rotate(-90deg);
      }
      .ga-ring-track {
        fill: none;
        stroke: #21262d;
        stroke-width: 9;
      }
      .ga-ring-fill {
        fill: none;
        stroke: #1f6feb;
        stroke-width: 9;
        stroke-linecap: round;
        transition: stroke-dashoffset .3s ease, stroke .3s ease;
      }
      .ga-ring-center {
        position: absolute;
        inset: 0;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        line-height: 1.15;
        pointer-events: none;
      }
      .ga-ring-step {
        font-size: 12px;
        font-weight: 600;
        color: #58a6ff;
        letter-spacing: 0.03em;
        margin-bottom: 2px;
      }
      .ga-ring-pct {
        font-size: 24px;
        font-weight: 700;
        color: #f0f6fc;
      }
      .ga-ring-mb {
        margin-top: 4px;
        font-size: 12px;
        font-weight: 500;
        color: #8b949e;
      }
      #custom-gen-status {
        font-size: 13px;
        color: #8b949e;
        text-align: center;
        max-width: 340px;
      }
    </style>
    <aside id=\"custom-domain-sidebar\">
      <div class=\"sidebar-header\">
        <div class=\"sidebar-title\">Domains (A–Z)</div>
        <select id=\"custom-lang-select\" autocomplete=\"off\" data-default-lang=\"${TARGET_LANG}\" title=\"Sprache / Language\">$(printf "%s" "$lang_options_html" | awk -v lang="${TARGET_LANG}" '{ target = "value=\"" lang "\""; idx = index($0, target); if (idx > 0) { $0 = substr($0, 1, idx + length(target) - 1) " selected" substr($0, idx + length(target)); } print }')</select>
      </div>
      <input type=\"search\" id=\"custom-domain-search\" placeholder=\"Domain suchen...\" autocomplete=\"off\">
      <div id=\"custom-domain-list\">${nav_links}</div>
      <div style=\"margin-top:auto;padding-top:12px;border-top:1px solid #232d42;display:flex;flex-direction:column;gap:8px;\">
        <button type=\"button\" id=\"custom-log-btn\" style=\"display:flex;align-items:center;justify-content:center;gap:6px;width:100%;padding:8px 10px;border-radius:8px;background:rgba(59,130,246,0.14);border:1px solid rgba(59,130,246,0.38);color:#93c5fd;font-size:12.5px;font-weight:600;cursor:pointer;\">Log anzeigen</button>
        <a href=\"/login.php?logout=1\" id=\"custom-logout-btn\" style=\"display:flex;align-items:center;justify-content:center;gap:6px;padding:8px 10px;border-radius:8px;background:rgba(239,68,68,0.12);border:1px solid rgba(239,68,68,0.32);color:#fca5a5;text-decoration:none;font-size:12.5px;font-weight:600;\">Abmelden / Logout</a>
        <div id=\"custom-version-box\" data-current-version=\"${APP_VERSION:-1.0.0}\" style=\"text-align:center;font-size:11.5px;color:#94a3b8;line-height:1.35;padding-top:2px;\">v${APP_VERSION:-1.0.0}</div>
      </div>
    </aside>
    <div id=\"custom-gen-overlay\">
      <div class=\"ga-ring-box\">
        <svg class=\"ga-ring-svg\" viewBox=\"0 0 120 120\">
          <circle class=\"ga-ring-track\" cx=\"60\" cy=\"60\" r=\"50\"></circle>
          <circle id=\"custom-gen-ring\" class=\"ga-ring-fill\" cx=\"60\" cy=\"60\" r=\"50\" stroke-dasharray=\"314.16\" stroke-dashoffset=\"314.16\"></circle>
        </svg>
        <div class=\"ga-ring-center\">
          <span id=\"custom-gen-step\" class=\"ga-ring-step\">0/12</span>
          <span id=\"custom-gen-pct\" class=\"ga-ring-pct\">0%</span>
          <span id=\"custom-gen-mb\" class=\"ga-ring-mb\">0.0 MB</span>
        </div>
      </div>
      <div id=\"custom-gen-status\">Sprache wird aktualisiert...</div>
      <div id=\"custom-gen-sub\" style=\"font-size:12px;color:#8b949e;\">Generating report...</div>
    </div>
    <script>
      (function() {
        var input = document.getElementById('custom-domain-search');
        var list = document.getElementById('custom-domain-list');
        if (input && list) {
          input.addEventListener('input', function() {
            var q = this.value.toLowerCase().trim();
            var links = list.getElementsByTagName('a');
            for (var i = 0; i < links.length; i++) {
              var txt = links[i].textContent.toLowerCase();
              links[i].style.display = txt.indexOf(q) !== -1 ? 'block' : 'none';
            }
          });
        }
      })();
    </script>
    <script>
${INJECT_JS}
      function gaUiLang() {
        var l = (window.__gaTargetLang || '').toLowerCase();
        if (!l) {
          var sel = document.getElementById('custom-lang-select');
          if (sel && sel.value) l = String(sel.value).toLowerCase();
        }
        if (!l && document.documentElement && document.documentElement.lang) {
          l = String(document.documentElement.lang).toLowerCase();
        }
        return l.indexOf('de') === 0 ? 'de' : 'en';
      }
      function gaMsg(key, arg) {
        var isEn = gaUiLang() === 'en';
        if (key === 'starting') return isEn ? 'Starting...' : 'Starte...';
        if (key === 'processing') return (isEn ? 'Processing ' : 'Verarbeite ') + (arg || '') + '...';
        if (key === 'done') return isEn ? 'Done (100%)' : 'Fertig (100%)';
        return arg || '';
      }

      function updateGenRing(pct, mb, done, total) {
        const ring = document.getElementById('custom-gen-ring');
        const stepEl = document.getElementById('custom-gen-step');
        const pctEl = document.getElementById('custom-gen-pct');
        const mbEl = document.getElementById('custom-gen-mb');
        const circ = 2 * Math.PI * 50;
        const clamped = Math.max(0, Math.min(100, Number(pct) || 0));
        if (ring) {
          ring.style.strokeDasharray = circ.toFixed(2);
          ring.style.strokeDashoffset = (circ * (1 - clamped / 100)).toFixed(2);
        }
        if (stepEl && typeof done !== 'undefined' && typeof total !== 'undefined' && Number(total) > 0) {
          stepEl.textContent = Number(done) + '/' + Number(total);
        }
        if (pctEl) pctEl.textContent = Math.round(clamped) + '%';
        if (mbEl && typeof mb !== 'undefined' && mb !== null) {
          mbEl.textContent = Number(mb).toFixed(1) + ' MB';
        }
      }

      (function attachLangProgressPoll() {
        const overlay = document.getElementById('custom-gen-overlay');
        const statusEl = document.getElementById('custom-gen-status');
        const sel = document.getElementById('custom-lang-select');
        if (sel && sel.dataset && sel.dataset.defaultLang) {
          sel.value = sel.dataset.defaultLang;
        }
        if (!overlay) return;
        let timer = null;

        async function pollOnce() {
          try {
            const res = await fetch('gen-lang.php?action=status', { cache: 'no-store' });
            if (!res.ok) return;
            const data = await res.json();
            if (!data || data.ok === false) return;
            var isDone = (data.running === false && Number(data.pct) >= 100);
            if (window.__gaLangSwitching && isDone) return;
            if (!isDone) window.__gaLangSwitching = false;
            if (Number(data.total) > 0) window.__gaLastTotal = Number(data.total);
            updateGenRing(data.pct, data.mb, data.done, data.total);
            if (statusEl) {
              if (isDone) {
                statusEl.textContent = gaMsg('done');
              } else if (data.domain && String(data.domain).toLowerCase() !== 'done' && String(data.domain).toLowerCase() !== 'fertig') {
                statusEl.textContent = gaMsg('processing', data.domain);
              }
            }
          } catch (_) {}
        }

        function startPolling() {
          if (timer) clearInterval(timer);
          window.__gaLangSwitching = true;
          if (sel && sel.value) window.__gaTargetLang = String(sel.value).toLowerCase();
          var oldBar = document.getElementById('custom-gen-bar');
          if (oldBar) oldBar.style.display = 'none';
          var initTot = Number(window.__gaLastTotal || 10);
          if (typeof updateGenRing === 'function') updateGenRing(0, 0, 0, initTot);
          if (statusEl) statusEl.textContent = gaMsg('starting');
          timer = setInterval(pollOnce, 300);
        }

        function stopPolling() {
          if (timer) {
            clearInterval(timer);
            timer = null;
          }
        }

        const mo = new MutationObserver(() => {
          const vis = window.getComputedStyle(overlay).display !== 'none';
          if (vis) startPolling();
          else stopPolling();
        });
        mo.observe(overlay, { attributes: true, attributeFilter: ['style', 'class'] });

        if (sel) {
          sel.addEventListener('change', () => {
            window.__gaTargetLang = String(sel.value || '').toLowerCase();
            updateGenRing(0, 0, 0, 12);
            startPolling();
          });
        }
      })();
      updateGenRing(0, 0);
    </script>"

    log_msg "Domain: ${dom} (${#logs[@]} Logdateien)"
    tmp_html=$(mktemp "${OUT_DIR}/.${dom}.XXXXXX.html")
    if [ "${DB_ONLY:-0}" = "1" ]; then
      if [ -t 1 ]; then
        printf "    \033[36m[DB]\033[0m Uebernehme Daten in die DB (%s) – bitte warten..." "$dom"
      fi
      err_snip=$(goaccess \
        --log-format="$KEYHELP_FMT" \
        --date-format="$DATE_FMT" \
        --time-format="$TIME_FMT" \
        --db-path="$db_dir" \
        --restore \
        $GEOIP_OPT \
        --no-global-config \
        -o "$tmp_html" 2>&1 >/dev/null | head -n 25)
      if [ -t 1 ]; then
        if [ -s "$tmp_html" ]; then
          printf "\r\033[2K    \033[32m[OK]\033[0m Daten in DB übernommen (%s).\n" "$dom"
        else
          printf "\r\033[2K"
        fi
      fi
    else
      err_snip=$(
        {
          python3 - "$dom" "${logs[@]}" <<'PYEOF'
import gzip, os, sys, time

dom_name = sys.argv[1] if len(sys.argv) > 1 else ""
paths = list(reversed(sys.argv[2:]))
total = sum(os.path.getsize(p) for p in paths if os.path.isfile(p))
sent_raw = 0
last_draw = 0.0
tty = None
try:
    tty = open("/dev/tty", "w", encoding="utf-8", errors="replace")
except OSError:
    tty = sys.stderr if sys.stderr.isatty() else None

for p in paths:
    if not os.path.isfile(p) or os.path.getsize(p) == 0:
        continue
    opener = gzip.open if p.endswith(".gz") else open
    try:
        with opener(p, "rb") as f:
            while True:
                chunk = f.read(1048576)
                if not chunk:
                    break
                sys.stdout.buffer.write(chunk)
                if p.endswith(".gz"):
                    sent_raw = min(total, sent_raw + max(1, len(chunk) // 6))
                else:
                    sent_raw = min(total, sent_raw + len(chunk))
                now = time.monotonic()
                if tty and (now - last_draw >= 0.12):
                    if total > 0:
                        pct = min(99, int(sent_raw * 100 / total))
                        tty.write(f"\r    \033[38;5;208m[IN]\033[0m Import: {pct:3d}% ({sent_raw / 1048576:.1f} / {total / 1048576:.1f} MB)   ")
                    else:
                        tty.write(f"\r    -> Import: {sent_raw / 1048576:.1f} MB   ")
                    tty.flush()
                    last_draw = now
    except OSError:
        continue

sys.stdout.buffer.flush()
if tty:
    tty.write(f"\r    \033[38;5;208m[IN]\033[0m Import: 100% ({total / 1048576:.1f} MB)                    \n")
    tty.write(f"    \033[36m[DB]\033[0m Uebernehme Daten in die DB ({dom_name}) – bitte warten...")
    tty.flush()
    tty.close()
PYEOF
        } | goaccess - \
          --log-format="$KEYHELP_FMT" \
          --date-format="$DATE_FMT" \
          --time-format="$TIME_FMT" \
          --db-path="$db_dir" \
          --persist \
          --restore \
          $GEOIP_OPT \
          --no-global-config \
          --invalid-requests=/dev/null \
          -o "$tmp_html" 2>&1 >/dev/null | head -n 25
      )
      if [ -t 1 ]; then
        if [ -s "$tmp_html" ]; then
          printf "\r\033[2K    \033[32m[OK]\033[0m Daten in DB übernommen (%s).\n" "$dom"
        else
          printf "\r\033[2K"
        fi
      fi
    fi

    if [ -s "$tmp_html" ]; then
      printf '\n%s\n' "$NAV_BAR" >> "$tmp_html"
      mv -f "$tmp_html" "${OUT_DIR}/${dom}.html"
      chown "${KH_USER}:${KH_USER}" "${OUT_DIR}/${dom}.html" 2>/dev/null || true
      chmod 644 "${OUT_DIR}/${dom}.html"
      fsize=$(du -h "${OUT_DIR}/${dom}.html" | cut -f1)
      echo -e "    ${C_GREEN}[OK]${C_RESET} Fertig: ${C_GRAY}${OUT_DIR}/${dom}.html${C_RESET}"
      done_pct=$(( idx * 100 / (total_doms > 0 ? total_doms : 1) ))
      write_gen_progress "$done_pct" "$dom" "$idx" "$total_doms" true
      log_msg "  OK: ${dom}.html (${fsize})"
    else
      rm -f "$tmp_html"
      echo "    -> Warnung: Kein Report fuer ${dom} erzeugt."
      log_msg "  FEHLER: Kein Report fuer ${dom} erzeugt."
      [ -n "$err_snip" ] && printf "%s\n" "$err_snip" | sed "s/^/    [goaccess] /" >> "$LOG_FILE"
    fi
  done

  write_gen_progress 100 "" "${total_doms}" "${total_doms}" false
done

  if [ -n "${DB_BASE:-}" ] && [ -f "$LOG_FILE" ]; then
    mkdir -p "$DB_BASE"
    cp -f "$LOG_FILE" "${DB_BASE}/goaccess-update.log" 2>/dev/null || true
    [ -n "${KH_USER:-}" ] && chown "${KH_USER}:${KH_USER}" "${DB_BASE}/goaccess-update.log" 2>/dev/null || true
    chmod 0644 "${DB_BASE}/goaccess-update.log" 2>/dev/null || true
  fi
echo "${C_GREEN}${C_BOLD}Alle Laeufe abgeschlossen.${C_RESET}"
for CONF_FILE in /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/*.conf; do
  [ -e "$CONF_FILE" ] || continue
  KH_USER=""
  STATS_DOMAIN=""
  OUT_DIR=""
  INDEX_DOMAIN=""
  HIDE_NAV_DOMAINS=""
  # shellcheck disable=SC1090
  source "$CONF_FILE"
  [ -z "$KH_USER" ] && continue
  OUT_DIR="${OUT_DIR:-/home/users/${KH_USER}/www/${STATS_DOMAIN}}"
  [ -d "$OUT_DIR" ] || continue

  first_html=$(python3 - "$OUT_DIR" "$INDEX_DOMAIN" "$HIDE_NAV_DOMAINS" << 'PYFIRST'
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
idx_dom = sys.argv[2].strip()
hidden = {d.strip().lower() for d in sys.argv[3].replace(",", " ").split() if d.strip()}

if idx_dom and (out_dir / f"{idx_dom}.html").is_file():
    print(out_dir / f"{idx_dom}.html")
    sys.exit(0)

for f in sorted(out_dir.glob("*.html")):
    if f.name == "index.html" or f.name.startswith("."):
        continue
    if f.stem.lower() in hidden:
        continue
    print(f)
    sys.exit(0)
PYFIRST
)
  if [ -n "$first_html" ] && [ -f "$first_html" ]; then
    cp -f "$first_html" "${OUT_DIR}/index.html"
    chown "${KH_USER}:${KH_USER}" "${OUT_DIR}/index.html"
    chmod 644 "${OUT_DIR}/index.html"
  fi
done

log_msg "=== Alle Laeufe abgeschlossen ==="