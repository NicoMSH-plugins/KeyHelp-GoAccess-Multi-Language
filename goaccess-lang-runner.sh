#!/bin/bash
DB_BASE="/var/lib/goaccess-db"
[ -r /etc/goaccess-dashboard.conf ] && source /etc/goaccess-dashboard.conf
REQ_FILE="${DB_BASE}/.lang_request"
LOCK_FILE="${DB_BASE}/.lang_runner.lock"
PROG_FILE="${DB_BASE}/.gen_progress"

exec 9>"$LOCK_FILE"
flock -w 120 9 || exit 1

UPD_FILE="${DB_BASE}/.update_request"
if [ -f "$UPD_FILE" ]; then
  write_runner_progress 15 "Git Pull..." 0 1 true "0.0"
  su -s /bin/sh keyhelp -c "git -C /home/keyhelp/www/keyhelp/dashboard-layout/goaccess pull --ff-only" >/dev/null 2>&1 || true
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
  cp -f /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/goaccess-lang.path /etc/systemd/system/goaccess-lang.path 2>/dev/null || true
  cp -f /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/goaccess-lang.service /etc/systemd/system/goaccess-lang.service 2>/dev/null || true
  systemctl daemon-reload >/dev/null 2>&1 || true
  write_runner_progress 75 "Rebuild..." 0 1 true "0.0"
  /usr/local/bin/update-goaccess.sh >/dev/null 2>&1 || true
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
