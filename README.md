# KeyHelp GoAccess Multi-Language Dashboard

A multi-language GoAccess web analytics dashboard and live language switcher for KeyHelp domains. It generates per-domain HTML reports with a searchable domain sidebar, persists GoAccess databases across runs, and switches report languages on the fly via a `systemd` path/service watcher (`goaccess-lang.path` / `goaccess-lang.service`) and a session/CSRF-protected PHP endpoint (`gen-lang.php`).

> [!IMPORTANT]
>
> **Requirements**
>
> - **Server:** Debian/Ubuntu Linux server with `root` SSH access, `systemd`, `bash`, and `locale-gen`.
> - **GoAccess:** `goaccess` installed on the system (see [Step 1](#step-1-install-goaccess-if-not-installed)).
> - **KeyHelp:** A dedicated subdomain or domain in KeyHelp (e.g. `stats.example.com`) serving the generated HTML reports, plus `/var/lib/goaccess-db` added to PHP `open_basedir`.
> - **Permissions:** Repository files under `/home/keyhelp/www/keyhelp/dashboard-layout` are automatically set to `keyhelp:keyhelp` at the start of `./install`.

***

## Features

- Automatically discovers all active domains with access logs under `/home/users/<KH_USER>/logs/` and generates individual HTML reports (`<domain>.html`).
- Version check under sidebar buttons (`#custom-version-box` in `dashboard-inject.js`) comparing the local `VERSION` against the Git branch (`main`) with a 6-hour `localStorage` cache (no GitHub releases required).
- Injects a fixed, searchable domain navigation sidebar (`Domains (A–Z)`) and a live language selector (`#custom-lang-select`) into every generated report, keeping the selected language synced across reloads.
- Supports 12 languages (`de`, `en`, `es`, `fr`, `it`, `ja`, `ko`, `pt`, `ru`, `sv`, `uk`, `zh`) via UTF-8 system locales and stores the active language in `/var/lib/goaccess-db/.current_lang` so scheduled cron runs keep your selected language.
- Asynchronous report regeneration via `/var/lib/goaccess-db/.lang_request` and `goaccess-lang.path` with `flock` locking, a progress ring overlay, and a built-in log viewer (`log-view.php`).
- Hardened `gen-lang.php` endpoint requiring an active KeyHelp session cookie, same-origin request headers, and a valid `X-CSRF-Token`.
- Multi-user capable via separate `*.conf` files in `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/`.

***

## File Structure

```text
dashboard-layout/goaccess/
├── README.md                    # Full installation and usage documentation
├── VERSION                      # Current dashboard version used for Git branch update checks
├── .gitignore                   # Ignores local *.conf files while keeping *.conf.example
├── goaccess.conf.example        # Template for per-user configuration (<user>.conf)
├── install                      # Interactive installer (permissions, locales, dirs, scripts, systemd, cron)
├── uninstall                    # Removes systemd units, cronjob, /usr/local/bin/ scripts and generated files
├── update-goaccess.sh           # Generates HTML reports across *.conf files, mirrors logs & injects UI
├── goaccess-lang-runner.sh      # Systemd runner with flock locking and trigger cleanup
├── goaccess-lang.path           # Systemd path unit watching .lang_request
├── goaccess-lang.service        # Systemd oneshot service running update-goaccess.sh
├── gen-lang.php                 # Session, same-origin & CSRF-protected trigger endpoint
├── log-view.php                 # Session-protected log viewer endpoint for update logs
├── login.php                    # Authentication gate for the statistics subdomain
└── assets/
    └── dashboard-inject.js      # Client-side language dropdown, progress overlay & CSRF logic
```

***

## Step-by-Step Installation

### Step 1: Create a Statistics Subdomain in KeyHelp

1. Log in to your **KeyHelp** panel.
2. Go to **Domains -> Add Domain** (or **Subdomains -> Add Subdomain**) and create a dedicated subdomain for your analytics dashboard, for example `stats.example.com`, assigned to the target KeyHelp user (e.g. `exampleuser`).
3. Enable **Let's Encrypt SSL** for `stats.example.com` so the dashboard and PHP session cookies work over HTTPS.

### Step 2: Allow `/var/lib/goaccess-db` in PHP `open_basedir`

`gen-lang.php` writes the language trigger file `/var/lib/goaccess-db/.lang_request` so `systemd` can regenerate reports as `root`. PHP must be allowed to access `/var/lib/goaccess-db`:

1. In **KeyHelp**, open **Users** and click **Edit** on the KeyHelp user that owns `stats.example.com`.
2. Switch to the **PHP** tab.
3. Locate the **`open_basedir`** field and append `:/var/lib/goaccess-db` to the existing path list (e.g. `##DOCROOT##/www:##DOCROOT##/files:##DOCROOT##/tmp:/var/lib/goaccess-db`).
4. Click **Save**.

### Step 3: Get the Files onto Your Server

Clone or pull `https://github.com/NicoMSH-plugins/KeyHelp-GoAccess-Multi-Language` into `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess`:

If `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess` does not exist yet:

```bash
mkdir -p /home/keyhelp/www/keyhelp/dashboard-layout
cd /home/keyhelp/www/keyhelp/dashboard-layout
git clone https://github.com/NicoMSH-plugins/KeyHelp-GoAccess-Multi-Language.git goaccess
cd goaccess
chmod +x /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/install /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/uninstall
```

If `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess` already exists, pull or check out into it:

```bash
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
if [ -d .git ]; then
  git pull --ff-only origin main
else
  git init -b main
  git remote add origin https://github.com/NicoMSH-plugins/KeyHelp-GoAccess-Multi-Language.git
  git fetch origin main
  git reset --hard origin/main
fi
chmod +x /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/install /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/uninstall
```

Verify that the files are present:

```bash
ls -la /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
```

### Step 4: Run the Installer

Run `./install` as `root`. It sets directory ownership to `keyhelp:keyhelp` right at startup, guides you interactively through user/domain setup, domain filters, cron interval, and login credentials, and generates the initial reports:

```bash
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
chmod +x install uninstall
./install
```

The installer automatically:
- Sets `keyhelp:keyhelp` ownership on the GoAccess directory and marks scripts executable.
- Enables and generates the required UTF-8 locales in `/etc/locale.gen`.
- Creates `/var/lib/goaccess-db/<user>` with permissions for `<user>:www-data`.
- Installs `update-goaccess.sh` and `goaccess-lang-runner.sh` to `/usr/local/bin/`.
- Installs and enables `goaccess-lang.path` and `goaccess-lang.service`.
- Generates the initial HTML reports and sets up the root cronjob (with a custom minute interval and confirmation prompt).
- Configures `login.php`, `log-view.php`, `gen-lang.php`, `.htaccess`, and `.htpasswd` in your statistics webroot (`OUT_DIR`).

> [!NOTE]
> **Supporting Multiple KeyHelp Users & Custom Document Root:** You can add additional users directly via the installer prompt when re-running `./install`. By default, `OUT_DIR` is `/home/users/<KH_USER>/www/<STATS_DOMAIN>` – if your subdomain in KeyHelp uses a custom document root path, update `OUT_DIR` in `<user>.conf` and run `./install` again.

### Step 5: Verify Status & Generated Reports

Check that `goaccess-lang.path`, the root cronjob, and the generated HTML reports are in place:

```bash
systemctl is-active goaccess-lang.path
crontab -l | grep update-goaccess.sh
ls -la /home/users/<KH_USER>/www/<STATS_DOMAIN>/*.html
```

### Step 6: Open & Use GoAccess in the Browser

1. Make sure you have an active session in your **KeyHelp** panel (so your browser holds a valid KeyHelp session cookie for CSRF-protected language switching).
2. Open your statistics subdomain in the browser by navigating directly to one of your generated domain reports:
   `https://stats.example.com/<your-domain.tld>.html`
3. Use the **left sidebar** (`Domains (A–Z)`) and the search input (`Domain suchen...`) to switch between all analyzed domains.
4. Use the **language dropdown** in the top-right corner of the sidebar to switch the report language. A progress ring overlay appears while `systemd` regenerates all reports in the selected language, and the page reloads automatically once finished. You can also open the update log anytime via **Log anzeigen**.

***

## Updating & Uninstalling

### Updating

Updates can be triggered directly from the **Update** button in the bottom-left sidebar of your statistics dashboard whenever a new release is available. The background runner automatically pulls the latest changes from `main`, updates scripts, PHP endpoints, `systemd` units, GeoIP data, and GoAccess `1.12` if needed, rebuilds all reports, and logs every step in the Log Viewer (local `*.conf` files remain untouched).

### Uninstalling

To stop and remove the `systemd` units, cronjob, helper scripts under `/usr/local/bin/`, and generated files:

```bash
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
./uninstall
```

***

## Changelog

<details>
<summary>Show / Expand Changelog History</summary>

### v1.0.4 (2026-11-27)

- **Horizontal & Wide-View Layout Offset Fix:** Added dynamic sidebar offset calculation (`--ga-nav-offset` via `ResizeObserver` and viewport resize listener in `dashboard-inject.js`) with horizontal overflow handling so wide GoAccess report columns and panels are no longer clipped on the left.
- **Restored Sidebar Self-Update Button:** Removed a duplicate `const updBtn` declaration in `dashboard-inject.js` that prevented the injected script block from executing and rendering the update trigger button.

### v1.0.5 (2026-11-27)

- **Automatic GeoIP City Map (No Registration Required):** Automatically downloads and refreshes `GeoLite2-City.mmdb` under `/usr/share/GeoIP/GeoLite2-City.mmdb` (every 30 days via `update-goaccess.sh` and during `./install`) from a public mirror without requiring a MaxMind account, passing `--geoip-database` to GoAccess so the Geo Location world map and city markers render automatically.

### v1.0.6 (2026-11-27)

- **Non-Interactive Install & Cleanup:** Updated `install` and `uninstall` for reliable, non-interactive execution including full cleanup of `/usr/local/bin/goaccess` and `/usr/share/GeoIP/GeoLite2-City.mmdb`.
- **Layout & Sidebar Alignment:** Refined offset handling in `assets/dashboard-inject.js` across the custom domain sidebar, navigation icon bar, and main report container.
- **Granular Update Logging:** Expanded `log_msg` output in `update-goaccess.sh` so domain runs, log counts, and status entries appear completely in `goaccess-update.log` and the Log Viewer.
- **Auto-Update Step Logging:** Added detailed `[AUTO-UPDATE]` step logging (Git pull with commit hash, file sync, GeoIP check, GoAccess binary check, and user log synchronization) in `goaccess-lang-runner.sh` so automated UI updates remain fully visible in the Log Viewer.
- **Automated Runner Upgrades:** Extended `goaccess-lang-runner.sh` to sync `/usr/local/bin/VERSION`, ensure `GeoLite2-City.mmdb` is present, restart `goaccess-lang.path`, and non-interactively build GoAccess `1.9.4` when needed.

### v1.0.7 (2026-11-27)

- **GoAccess 1.12 Source Build:** Updated `install` and `goaccess-lang-runner.sh` to build and upgrade GoAccess to `1.12` with `--enable-utf8`, `--enable-geoip=mmdb`, and `--with-openssl` (removing older apt-packaged `goaccess` installations automatically).
- **Complete Uninstall Cleanup:** Extended `uninstall` to also remove `/usr/local/etc/goaccess` left behind by source builds.

</details>
