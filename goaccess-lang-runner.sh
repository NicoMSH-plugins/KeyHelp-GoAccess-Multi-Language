#!/bin/bash
DB_BASE="/var/lib/goaccess-db"
[ -r /etc/goaccess-dashboard.conf ] && source /etc/goaccess-dashboard.conf
REQ_FILE="${DB_BASE}/.lang_request"
LOCK_FILE="${DB_BASE}/.lang_runner.lock"
PROG_FILE="${DB_BASE}/.gen_progress"

exec 9>"$LOCK_FILE"
flock -w 120 9 || exit 1

write_runner_progress() {
  local p_pct="$1"
  local p_dom="$2"
  local p_done="$3"
  local p_total="$4"
  local p_running="$5"
  local p_mb="${6:-0.0}"
  printf '{"pct":%s,"mb":%s,"domain":"%s","done":%s,"total":%s,"running":%s}\n'     "$p_pct" "$p_mb" "$p_dom" "$p_done" "$p_total" "$p_running" > "$PROG_FILE"
  chmod 0664 "$PROG_FILE" 2>/dev/null || true
  mkdir -p "${DB_BASE}/nicoweb" 2>/dev/null || true
  cp -f "$PROG_FILE" "${DB_BASE}/nicoweb/.gen_progress" 2>/dev/null || true
  chmod 0664 "${DB_BASE}/nicoweb/.gen_progress" 2>/dev/null || true
}

UPD_FILE="${DB_BASE}/.update_request"
if [ -f "$UPD_FILE" ]; then
  REPO_LOG="/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/goaccess-update.log"
  USER_LOG="${DB_BASE}/nicoweb/goaccess-update.log"
  mkdir -p "$(dirname "$USER_LOG")" 2>/dev/null || true
  UPD_TMP=$(mktemp /tmp/goaccess-autoupdate.XXXXXX)

  log_upd() {
    local line
    line=$(printf '[%s] [AUTO-UPDATE] %s' "$(date '+%Y-%m-%d %H:%M:%S')" "$1")
    printf '%s\n' "$line" >> "$UPD_TMP"
    printf '%s\n' "$line" >> "$REPO_LOG" 2>/dev/null || true
    printf '%s\n' "$line" >> "$USER_LOG" 2>/dev/null || true
    chown nicoweb:nicoweb "$USER_LOG" 2>/dev/null || true
  }

  log_upd "Starte automatisches Update (Trigger: ${UPD_FILE})"
  write_runner_progress 15 "Git Pull..." 0 1 true "0.0"
  if su -s /bin/sh keyhelp -c "HOME=/home/keyhelp git -C /home/keyhelp/www/keyhelp/dashboard-layout/goaccess fetch origin main && HOME=/home/keyhelp git -C /home/keyhelp/www/keyhelp/dashboard-layout/goaccess reset --hard origin/main" >>"$UPD_TMP" 2>&1; then
    NEW_COMMIT=$(su -s /bin/sh keyhelp -c "HOME=/home/keyhelp git -C /home/keyhelp/www/keyhelp/dashboard-layout/goaccess log -n 1 --oneline" 2>/dev/null || echo "unbekannt")
    log_upd "Git Pull erfolgreich: ${NEW_COMMIT}"
  else
    log_upd "WARNUNG: Git Pull fehlgeschlagen"
  fi

  write_runner_progress 45 "Sync..." 0 1 true "0.0"
  cp -f /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/update-goaccess.sh /usr/local/bin/update-goaccess.sh 2>/dev/null || true
  cp -f /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/goaccess-lang-runner.sh /usr/local/bin/goaccess-lang-runner.sh 2>/dev/null || true
  chmod +x /usr/local/bin/update-goaccess.sh /usr/local/bin/goaccess-lang-runner.sh 2>/dev/null || true
  if [ -d /home/users/nicoweb/www/stats.uaena.info ]; then
    for f in gen-lang.php login.php log-view.php; do
      [ -f "/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/${f}" ] && cp -f "/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/${f}" "/home/users/nicoweb/www/stats.uaena.info/${f}"
    done
    chown -R nicoweb:nicoweb /home/users/nicoweb/www/stats.uaena.info/login.php /home/users/nicoweb/www/stats.uaena.info/log-view.php /home/users/nicoweb/www/stats.uaena.info/gen-lang.php 2>/dev/null || true
    [ -f /home/users/nicoweb/www/stats.uaena.info/.htpasswd ] && chmod 0640 /home/users/nicoweb/www/stats.uaena.info/.htpasswd 2>/dev/null || true
    [ -f /home/users/nicoweb/www/stats.uaena.info/login.php ] && chmod 0640 /home/users/nicoweb/www/stats.uaena.info/login.php 2>/dev/null || true
  fi
  [ -f /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/VERSION ] && cp -f /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/VERSION /usr/local/bin/VERSION 2>/dev/null || true
  NEW_VER=$(cat /usr/local/bin/VERSION 2>/dev/null || echo "unbekannt")
  log_upd "Dateien & VERSION (${NEW_VER}) synchronisiert"

  if [ ! -s /usr/share/GeoIP/GeoLite2-City.mmdb ]; then
    log_upd "GeoLite2-City.mmdb fehlt – starte Download..."
    mkdir -p /usr/share/GeoIP 2>/dev/null || true
    if curl -fsSL --max-time 90 "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb" -o /usr/share/GeoIP/GeoLite2-City.mmdb.tmp.$$ 2>/dev/null \
      && [ -s /usr/share/GeoIP/GeoLite2-City.mmdb.tmp.$$ ] \
      && chmod 644 /usr/share/GeoIP/GeoLite2-City.mmdb.tmp.$$ \
      && mv -f /usr/share/GeoIP/GeoLite2-City.mmdb.tmp.$$ /usr/share/GeoIP/GeoLite2-City.mmdb; then
      log_upd "GeoLite2-City.mmdb erfolgreich installiert"
    else
      rm -f /usr/share/GeoIP/GeoLite2-City.mmdb.tmp.$$
      log_upd "WARNUNG: GeoLite2-City.mmdb Download fehlgeschlagen"
    fi
  else
    log_upd "GeoLite2-City.mmdb bereits vorhanden"
  fi

  GA_TARGET_VER="1.12"
  GA_CUR_VER=$(/usr/local/bin/goaccess --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || echo "0.0.0")
  GA_MAJOR=$(printf '%s' "$GA_CUR_VER" | cut -d. -f1)
  GA_MINOR=$(printf '%s' "$GA_CUR_VER" | cut -d. -f2)
  GA_OK=0
  if { [ "${GA_MAJOR:-0}" -gt 1 ] || { [ "${GA_MAJOR:-0}" -eq 1 ] && [ "${GA_MINOR:-0}" -ge 12 ]; }; } && /usr/local/bin/goaccess --version 2>/dev/null | grep -q -- '--enable-geoip=mmdb'; then
    GA_OK=1
  fi

  if [ "$GA_OK" -eq 0 ]; then
    log_upd "GoAccess (${GA_CUR_VER}) < ${GA_TARGET_VER} – starte nicht-interaktiven Build..."
    write_runner_progress 60 "GoAccess ${GA_TARGET_VER}..." 0 1 true "0.0"
    (
      export DEBIAN_FRONTEND=noninteractive
      if dpkg-query -W -f='${Status}' goaccess 2>/dev/null | grep -q "install ok installed"; then
        apt-get purge -y -qq goaccess >/dev/null 2>&1 || true
      fi
      MISSING_PKGS=""
      for _pkg in build-essential libncursesw5-dev libmaxminddb-dev libssl-dev curl tar; do
        if ! dpkg-query -W -f='${Status}' "$_pkg" 2>/dev/null | grep -q "install ok installed"; then
          MISSING_PKGS="$MISSING_PKGS $_pkg"
        fi
      done
      if [ -n "$MISSING_PKGS" ]; then
        apt-get update -qq >/dev/null 2>&1 || true
        # shellcheck disable=SC2086
        apt-get install -y -qq $MISSING_PKGS >/dev/null 2>&1 || true
      fi
      tmp_build=$(mktemp -d /tmp/goaccess-build.XXXXXX)
      if curl -fsSL --max-time 120 "https://tar.goaccess.io/goaccess-${GA_TARGET_VER}.tar.gz" -o "${tmp_build}/goaccess-${GA_TARGET_VER}.tar.gz" 2>/dev/null; then
        tar -xzf "${tmp_build}/goaccess-${GA_TARGET_VER}.tar.gz" -C "${tmp_build}" 2>/dev/null
        cd "${tmp_build}/goaccess-${GA_TARGET_VER}" && ./configure --enable-utf8 --enable-geoip=mmdb --with-openssl >/dev/null 2>&1 && make -j"$(nproc)" >/dev/null 2>&1 && make install >/dev/null 2>&1
      fi
      rm -rf "${tmp_build}"
    ) || true
    log_upd "GoAccess Build abgeschlossen: $(/usr/local/bin/goaccess --version 2>/dev/null | head -n 1)"
  else
    log_upd "GoAccess ${GA_CUR_VER} (>= ${GA_TARGET_VER}) bereits installiert – Build uebersprungen"
  fi

  cp -f /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/goaccess-lang.path /etc/systemd/system/goaccess-lang.path 2>/dev/null || true
  cp -f /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/goaccess-lang.service /etc/systemd/system/goaccess-lang.service 2>/dev/null || true
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart goaccess-lang.path >/dev/null 2>&1 || true
  log_upd "Systemd-Units aktualisiert – starte Report-Rebuild..."

  write_runner_progress 75 "Rebuild..." 0 1 true "0.0"
  /usr/local/bin/update-goaccess.sh >/dev/null 2>&1 || true

  # update-goaccess.sh leert REPO_LOG zu Beginn; Auto-Update-Summary wieder anhaengen & ins User-Log syncen
  {
    printf '\n'
    cat "$UPD_TMP"
    printf '[%s] [AUTO-UPDATE] Automatisches Update komplett abgeschlossen\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  } >> "$REPO_LOG" 2>/dev/null || true
  cp -f "$REPO_LOG" "$USER_LOG" 2>/dev/null || true
  chown nicoweb:nicoweb "$USER_LOG" 2>/dev/null || true
  chmod 0644 "$USER_LOG" 2>/dev/null || true
  rm -f "$UPD_TMP"

  write_runner_progress 100 "Fertig" 1 1 false "0.0"
  rm -f "$UPD_FILE"
  exit 0
fi

[ -f "$REQ_FILE" ] || exit 0
LANG_CODE=$(tr -cd 'a-z' < "$REQ_FILE" | head -c 2)


get_active_dom_count() {
  local cnt=0 d bn log_base excl_raw
  local -a excl_arr=()
  for cf in /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/*.conf; do
    [ -f "$cf" ] || continue
    log_base=$(sed -n 's/^LOG_BASE="\?\([^"]*\)"\?$/\1/p' "$cf" | head -n1)
    excl_raw=$(sed -n 's/^EXCLUDE_DOMAINS="\?\([^"]*\)"\?$/\1/p' "$cf" | head -n1)
    [ -n "$log_base" ] && [ -d "$log_base" ] || continue
    read -r -a excl_arr <<< "$excl_raw"
    for d in "$log_base"/*; do
      [ -d "$d" ] || continue
      bn=$(basename "$d")
      [[ " ${excl_arr[*]} " == *" $bn "* ]] && continue
      if compgen -G "$d/*access.log*" >/dev/null || compgen -G "$d/*.log*" >/dev/null; then
        cnt=$((cnt + 1))
      fi
    done
    [ "$cnt" -gt 0 ] && { echo "$cnt"; return 0; }
  done
  echo 10
}

if [ -n "$LANG_CODE" ]; then
  if [ "$LANG_CODE" = "de" ]; then
    _TXT_START="Starte..."
    _TXT_DONE="Fertig"
  else
    _TXT_START="Starting..."
    _TXT_DONE="Done"
  fi
  ACTIVE_DOMS=$(get_active_dom_count)
  write_runner_progress 0 "$_TXT_START" 0 "$ACTIVE_DOMS" true "0.0"
  TARGET_LANG="$LANG_CODE" DB_ONLY=1 /usr/local/bin/update-goaccess.sh >/dev/null 2>&1
  LAST_MB=$(awk -F'"mb":' '{split($2,a,","); print a[1]+0}' "$PROG_FILE" 2>/dev/null)
  [ -z "$LAST_MB" ] && LAST_MB="0.0"
  ACTIVE_DOMS=$(get_active_dom_count)
  write_runner_progress 100 "$_TXT_DONE" "$ACTIVE_DOMS" "$ACTIVE_DOMS" false "$LAST_MB"
fi

rm -f "$REQ_FILE"
exit 0
