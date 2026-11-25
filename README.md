# KeyHelp GoAccess Multi-Language Dashboard

A multi-language GoAccess report generator and live language switcher for KeyHelp domains, using a systemd path/service watcher (`goaccess-lang.path` / `goaccess-lang.service`) and a session/CSRF-protected PHP trigger endpoint (`gen-lang.php`) configured via `*.conf` files in the `goaccess/` directory.

## Requirements

- Linux server with `root` access, `systemd`, `goaccess`, `bash`, and `locale-gen`.
- Existing KeyHelp user with domain access logs (`LOG_BASE`) and a target webroot (`OUT_DIR`) for generated HTML reports.
- `/var/lib/goaccess-db` allowed in PHP `open_basedir` for the web context executing `gen-lang.php`.
- Repository files under `/home/keyhelp/www/keyhelp/dashboard-layout` owned by `keyhelp:keyhelp`.

## File Structure

- `README.md` – Documentation and setup guide
- `goaccess.conf.example` – Configuration template for creating local `<user>.conf` files
- `install.sh` – Interactive installer (locales, directories, scripts, systemd units)
- `uninstall.sh` – Removes systemd units and `/usr/local/bin/` scripts
- `update-goaccess.sh` – Generates HTML reports across `*.conf` files and injects sidebar/language UI
- `goaccess-lang-runner.sh` – Systemd runner with `flock` locking and trigger cleanup
- `goaccess-lang.path` – Systemd path unit watching `.lang_request`
- `goaccess-lang.service` – Systemd oneshot service running the report generator
- `gen-lang.php` – Session, same-origin, and CSRF-protected endpoint for language switching
- `assets/dashboard-inject.js` – Client-side language dropdown, progress overlay, and CSRF handling

## Step-by-Step Installation

### Step 1: Ensure the Repository Is in Place

```bash
ls -la /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
```

### Step 2: Set Ownership and Permissions

```bash
chown -R keyhelp:keyhelp /home/keyhelp/www/keyhelp/dashboard-layout
chmod 755 /home/keyhelp/www/keyhelp/dashboard-layout /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
chmod +x /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/install.sh \
         /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/uninstall.sh \
         /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/update-goaccess.sh \
         /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/goaccess-lang-runner.sh
```

### Step 3: Run the Installer

```bash
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
./install.sh
```

### Step 4: Configure `*.conf` in `goaccess/` (Optional)

```bash
nano /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/*.conf
```

### Step 5: Generate Initial Reports & Test in Browser

```bash
/usr/local/bin/update-goaccess.sh
systemctl is-active goaccess-lang.path
```

Open your report page in the browser, perform a hard reload (**Ctrl + Shift + R**), and test switching languages in `#custom-lang-select`.

## Updating & Uninstalling

Update via Git and re-run `install.sh` if needed:

```bash
su -s /bin/sh keyhelp -c "git -C /home/keyhelp/www/keyhelp/dashboard-layout pull"
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess && ./install.sh
```

Remove systemd units and helper scripts:

```bash
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
./uninstall.sh
```
