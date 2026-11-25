cat << 'EOF' > /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/README.md
# KeyHelp GoAccess Multi-Language Dashboard

A multi-language GoAccess web analytics dashboard and live language switcher for KeyHelp domains. It generates per-domain HTML reports with a searchable domain sidebar, persists GoAccess databases across runs (`--persist` / `--restore`), protects access via a custom PHP login gate (`login.php`) backed by `.htpasswd`, provides a live Log Viewer overlay (`log-view.php`), and switches report languages on the fly via a `systemd` path/service watcher (`goaccess-lang.path` / `goaccess-lang.service`) and `gen-lang.php`.

> [!IMPORTANT]
>
> **Requirements**
>
> - **Server:** Debian/Ubuntu Linux server with `root` SSH access, `systemd`, `bash`, `php` (with PHP-FPM for the target KeyHelp user), and `locale-gen`.
> - **GoAccess:** `goaccess` installed on the system (see [Step 1](#step-1-install-goaccess-if-not-installed)).
> - **KeyHelp:** A dedicated subdomain or domain in KeyHelp (e.g. `stats.example.com`) serving the generated HTML reports, plus `/var/lib/goaccess-db` added to PHP `open_basedir`.
> - **Permissions:** Repository files under `/home/keyhelp/www/keyhelp/dashboard-layout` owned by `keyhelp:keyhelp`.

***

## Features

- Automatically discovers all active domains with access logs under `/home/users/<KH_USER>/logs/` and generates individual HTML reports (`<domain>.html`).
- Uses persistent GoAccess databases (`--db-path`, `--persist`, `--restore`, plus `DB_ONLY` support) so repeated cron runs do not duplicate historical data.
- Injects a fixed, searchable domain navigation sidebar (`Domains (A–Z)`), a live language selector (`#custom-lang-select`), a **Log anzeigen / View Log** button, and an **Abmelden / Logout** link (`/login.php?logout=1`) into every generated report.
- Provides a dark-themed Log Viewer overlay (`log-view.php`) reading the last 200 lines from `/var/lib/goaccess-db/goaccess-update.log` (hard-linked to `goaccess-update.log`) with fallback support, `Refresh`, `Close`, `ESC` handling, and automatic `DE`/`EN` labels.
- Replaces Apache `AuthType Basic` with a session-based PHP login gate (`login.php`) verifying credentials against `.htpasswd` (`$apr1$` Apache MD5-Crypt, bcrypt `$2y$`/`$2a$`/`$2b$`, `{SHA}`), with CSRF protection, brute-force rate limiting (5 attempts -> 60s lockout), automatic `DE`/`EN` language detection (`Accept-Language`), and `.htaccess` protection for `.htaccess` and `.htpasswd`.
- Supports 12 languages (`de`, `en`, `es`, `fr`, `it`, `ja`, `ko`, `pt`, `ru`, `sv`, `uk`, `zh`) via UTF-8 system locales and stores the active language in `/var/lib/goaccess-db/.current_lang` so scheduled cron runs preserve the selected language.
- Asynchronous report regeneration via `/var/lib/goaccess-db/.lang_request` and `goaccess-lang.path` with `flock` locking and a ring-based progress overlay in the browser.
- Hardened `gen-lang.php` endpoint requiring an active session cookie, same-origin request headers, and a valid `X-CSRF-Token`.
- Multi-user capable via separate `*.conf` files in `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/`.

***

## File Structure

```text
dashboard-layout/goaccess/
├── README.md                    # Full installation and usage documentation
├── .gitignore                   # Ignores local *.conf files while keeping *.conf.example
├── goaccess.conf.example        # Template for per-user configuration (<user>.conf)
├── install.sh                   # Interactive installer (locales, dirs, hardlink, scripts, PHP endpoints, systemd)
├── uninstall.sh                 # Removes systemd units, /usr/local/bin/ scripts, DBs, reports, logs & state files
├── update-goaccess.sh           # Generates persistent HTML reports across *.conf files, syncs log hardlink & injects UI
├── goaccess-lang-runner.sh      # Systemd runner with flock locking and trigger cleanup
├── goaccess-lang.path           # Systemd path unit watching .lang_request
├── goaccess-lang.service        # Systemd oneshot service running update-goaccess.sh
├── gen-lang.php                 # Session, same-origin & CSRF-protected language trigger endpoint
├── login.php                    # Custom PHP login gate verifying against .htpasswd with brute-force & CSRF protection
├── log-view.php                 # Authenticated JSON endpoint serving the last 200 log lines to the Log Viewer modal
└── assets/
    └── dashboard-inject.js      # Client-side sidebar search, language dropdown, progress overlay, log modal & CSRF logic
```

***

## Step-by-Step Installation

### Step 1: Install GoAccess (if not installed)

Connect to your server via SSH as `root` and check whether `goaccess` is already installed:

```bash
command -v goaccess && goaccess --version
```

If GoAccess is not installed yet, install it (along with the optional GeoIP database for country/city lookups):

```bash
apt-get update
apt-get install -y goaccess geoip-database
```

### Step 2: Create a Statistics Subdomain in KeyHelp

1. Log in to your **KeyHelp** panel.
2. Go to **Domains -> Add Domain** (or **Subdomains -> Add Subdomain**) and create a dedicated subdomain for your analytics dashboard, for example `stats.example.com`, assigned to the target KeyHelp user (e.g. `exampleuser`).
3. Enable **Let's Encrypt SSL** for `stats.example.com` so the dashboard and PHP session cookies (`Secure` flag) work over HTTPS.
4. Note the document root path of that subdomain (by default `/home/users/exampleuser/www/stats.example.com`).

### Step 3: Allow `/var/lib/goaccess-db` in PHP `open_basedir`

`gen-lang.php` writes `/var/lib/goaccess-db/.lang_request` for `systemd`, and `log-view.php` reads `/var/lib/goaccess-db/goaccess-update.log` (hard-linked to `goaccess-update.log` so PHP does not need traverse access into `/home/keyhelp` at `750`). PHP must be allowed to access `/var/lib/goaccess-db`:

1. In **KeyHelp**, open **Users** and click **Edit** on the KeyHelp user that owns `stats.example.com`.
2. Switch to the **PHP** tab.
3. Locate the **`open_basedir`** field and append `:/var/lib/goaccess-db` (separated by a single colon `:`, without duplicate colons `::`) to the existing path list (e.g. `##DOCROOT##/www:##DOCROOT##/files:##DOCROOT##/tmp:/var/lib/goaccess-db`).
4. Click **Save**.

### Step 4: Get the Files onto Your Server

Clone or pull `https://github.com/NicoMSH-plugins/KeyHelp-GoAccess-Multi-Language` into `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess`:

If `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess` does not exist yet:

```bash
mkdir -p /home/keyhelp/www/keyhelp/dashboard-layout
git clone https://github.com/NicoMSH-plugins/KeyHelp-GoAccess-Multi-Language.git /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
```

If `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess` already exists, pull or check out into it:

```bash
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
git pull || (git init && git remote add origin https://github.com/NicoMSH-plugins/KeyHelp-GoAccess-Multi-Language.git && git fetch origin && git checkout -t origin/main)
```

Verify that all 11 files and the `assets/` folder are present:

```bash
ls -la /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
```

### Step 5: Set Ownership and Permissions

Set ownership to `keyhelp:keyhelp` on the repository directory, make the shell scripts executable, and restrict `.htpasswd` and `login.php` appropriately:

```bash
chown -R keyhelp:keyhelp /home/keyhelp/www/keyhelp/dashboard-layout
chmod 755 /home/keyhelp/www/keyhelp/dashboard-layout /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
chmod +x /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/install.sh \
         /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/uninstall.sh \
         /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/update-goaccess.sh \
         /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/goaccess-lang-runner.sh
```

### Step 6: Run the Installer

Run `install.sh` as `root`. If no `*.conf` file exists yet, it prompts for your KeyHelp username and statistics domain and creates `<user>.conf` inside `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/`:

```bash
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
./install.sh
```

The installer automatically:
- Enables and generates the required UTF-8 locales in `/etc/locale.gen`.
- Creates `/var/lib/goaccess-db` and `/var/lib/goaccess-db/<user>` with permissions for `<user>:www-data`, and links `goaccess-update.log` to `/var/lib/goaccess-db/goaccess-update.log`.
- Installs `update-goaccess.sh` and `goaccess-lang-runner.sh` to `/usr/local/bin/`.
- Copies `gen-lang.php`, `login.php`, and `log-view.php` into your statistics subdomain webroot (`OUT_DIR`), ensures `.htaccess` protects `.htaccess` and `.htpasswd`, and sets `chmod 640` on `.htpasswd` and `login.php` (if present).
- Installs and enables `goaccess-lang.path` and `goaccess-lang.service`.

### Step 7: Configure `.htpasswd` & `<user>.conf` (and Additional Users)

1. Make sure an `.htpasswd` file exists in your statistics subdomain webroot (`OUT_DIR/.htpasswd`) with at least one user (`htpasswd -B` / `$apr1$` MD5-Crypt, bcrypt, or `{SHA}` are supported by `login.php`) and permissions `0640` (owned by `<user>:<webgroup>`).
2. Edit your generated `<user>.conf` in `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/` to exclude domains or adjust defaults:

```bash
nano /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/*.conf
```

Available options in `<user>.conf`:
- `KH_USER` – KeyHelp username whose logs should be parsed.
- `STATS_DOMAIN` – Subdomain serving the HTML reports.
- `EXCLUDE_DOMAINS` – Space-separated list of domains to skip completely (no report generated).
- `HIDE_NAV_DOMAINS` – Space-separated list of domains to generate reports for, but hide from the sidebar navigation.
- `DEFAULT_LANG` – Initial fallback language (`de`, `en`, `es`, `fr`, `it`, `ja`, `ko`, `pt`, `ru`, `sv`, `uk`, `zh`).

> [!NOTE]
> **Supporting Multiple KeyHelp Users:** Copy `goaccess.conf.example` to `<seconduser>.conf` inside `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/`, adjust `KH_USER` and `STATS_DOMAIN`, ensure `/var/lib/goaccess-db` is in that user's PHP `open_basedir`, and re-run `./install.sh`.

### Step 8: Generate Initial Reports & Set Up a Cronjob

Run the generator once manually to build the persistent GoAccess database, link `goaccess-update.log`, and create the initial HTML files:

```bash
/usr/local/bin/update-goaccess.sh
systemctl is-active goaccess-lang.path
```

Verify that HTML files and PHP endpoints were created in your statistics webroot:

```bash
ls -la /home/users/<KH_USER>/www/<STATS_DOMAIN>/*.html /home/users/<KH_USER>/www/<STATS_DOMAIN>/login.php /home/users/<KH_USER>/www/<STATS_DOMAIN>/log-view.php /home/users/<KH_USER>/www/<STATS_DOMAIN>/gen-lang.php
```

To keep your statistics up to date automatically without duplicating data (thanks to persistent GoAccess databases), add a root cronjob (e.g. every 15 minutes) via `crontab -e`:

```cron
*/15 * * * * /usr/local/bin/update-goaccess.sh >/dev/null 2>&1
```

### Step 9: Open & Use GoAccess in the Browser

1. Open your statistics subdomain in the browser:
   `https://stats.example.com/<your-domain.tld>.html`
2. Sign in via the custom PHP login page (`/login.php`) using a valid username and password from `.htpasswd` (automatically rendered in German for `de*` browsers or English otherwise).
3. Use the **left sidebar** (`Domains (A–Z)`) and the search input (`Domain suchen...`) to switch between all analyzed domains while keeping the bottom action buttons pinned.
4. Use the **language dropdown** in the top-right corner of the sidebar to switch the report language. A ring progress overlay appears while `systemd` regenerates all reports in the selected language, and the page reloads automatically once finished.
5. Click **Log anzeigen / View Log** at the bottom of the sidebar to inspect the latest log lines in the modal overlay (with `Refresh`, `Close`, and `ESC` support), or click **Abmelden / Logout** (`/login.php?logout=1`) to end your session.

***

## Updating & Uninstalling

### Updating

Pull the latest changes as `keyhelp` and re-run `install.sh` as `root` to update `/usr/local/bin/` scripts, PHP endpoints (`gen-lang.php`, `login.php`, `log-view.php`), the `/var/lib/goaccess-db/goaccess-update.log` hardlink, and `systemd` units (your local `*.conf` files are git-ignored and remain untouched):

```bash
su -s /bin/sh keyhelp -c "git -C /home/keyhelp/www/keyhelp/dashboard-layout/goaccess pull"
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess && ./install.sh
```

### Uninstalling

To stop and remove the `systemd` units, helper scripts under `/usr/local/bin/`, generated databases and reports (including `login.php`, `log-view.php`, `gen-lang.php`, `.htaccess`, and `.htpasswd`), state files (`.current_lang`, `.lang_request`, `.gen_progress`, `.update.log`), and `/var/lib/goaccess-db/goaccess-update.log`:

```bash
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
./uninstall.sh
```
EOF