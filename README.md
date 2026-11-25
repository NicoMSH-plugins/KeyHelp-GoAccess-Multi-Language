# KeyHelp GoAccess Multi-Language Dashboard

A multi-language GoAccess web analytics dashboard and live language switcher for KeyHelp domains. It generates per-domain HTML reports with a searchable domain sidebar, persists GoAccess databases across runs, and switches report languages on the fly via a `systemd` path/service watcher (`goaccess-lang.path` / `goaccess-lang.service`) and a session/CSRF-protected PHP endpoint (`gen-lang.php`).

> [!IMPORTANT]
>
> **Requirements**
>
> - **Server:** Debian/Ubuntu Linux server with `root` SSH access, `systemd`, `bash`, and `locale-gen`.
> - **GoAccess:** `goaccess` installed on the system (see [Step 1](#step-1-install-goaccess-if-not-installed)).
> - **KeyHelp:** A dedicated subdomain or domain in KeyHelp (e.g. `stats.example.com`) serving the generated HTML reports, plus `/var/lib/goaccess-db` added to PHP `open_basedir`.
> - **Permissions:** Repository files under `/home/keyhelp/www/keyhelp/dashboard-layout` owned by `keyhelp:keyhelp`.

***

## Features

- Automatically discovers all active domains with access logs under `/home/users/<KH_USER>/logs/` and generates individual HTML reports (`<domain>.html`).
- Injects a fixed, searchable domain navigation sidebar (`Domains (A–Z)`) and a live language selector (`#custom-lang-select`) into every generated report.
- Supports 12 languages (`de`, `en`, `es`, `fr`, `it`, `ja`, `ko`, `pt`, `ru`, `sv`, `uk`, `zh`) via UTF-8 system locales and stores the active language in `/var/lib/goaccess-db/.current_lang` so scheduled cron runs keep your selected language.
- Asynchronous report regeneration via `/var/lib/goaccess-db/.lang_request` and `goaccess-lang.path` with `flock` locking and a progress overlay in the browser.
- Hardened `gen-lang.php` endpoint requiring an active KeyHelp session cookie, same-origin request headers, and a valid `X-CSRF-Token`.
- Multi-user capable via separate `*.conf` files in `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/`.

***

## File Structure

```text
dashboard-layout/goaccess/
├── README.md                    # Full installation and usage documentation
├── .gitignore                   # Ignores local *.conf files while keeping *.conf.example
├── goaccess.conf.example        # Template for per-user configuration (<user>.conf)
├── install.sh                   # Interactive installer (locales, dirs, scripts, systemd)
├── uninstall.sh                 # Removes systemd units and /usr/local/bin/ scripts
├── update-goaccess.sh           # Generates HTML reports across *.conf files and injects UI
├── goaccess-lang-runner.sh      # Systemd runner with flock locking and trigger cleanup
├── goaccess-lang.path           # Systemd path unit watching .lang_request
├── goaccess-lang.service        # Systemd oneshot service running update-goaccess.sh
├── gen-lang.php                 # Session, same-origin & CSRF-protected trigger endpoint
└── assets/
    └── dashboard-inject.js      # Client-side language dropdown, progress overlay & CSRF logic
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
3. Enable **Let's Encrypt SSL** for `stats.example.com` so the dashboard and PHP session cookies work over HTTPS.
4. Note the document root path of that subdomain (by default `/home/users/exampleuser/www/stats.example.com`).

### Step 3: Allow `/var/lib/goaccess-db` in PHP `open_basedir`

`gen-lang.php` writes the language trigger file `/var/lib/goaccess-db/.lang_request` so `systemd` can regenerate reports as `root`. PHP must be allowed to access `/var/lib/goaccess-db`:

1. In **KeyHelp**, open **Users** and click **Edit** on the KeyHelp user that owns `stats.example.com`.
2. Switch to the **PHP** tab.
3. Locate the **`open_basedir`** field and append `:/var/lib/goaccess-db` to the existing path list (e.g. `##DOCROOT##/www:##DOCROOT##/files:##DOCROOT##/tmp:/var/lib/goaccess-db`).
4. Click **Save**.

### Step 4: Place the Files & Set Permissions

Ensure the `goaccess/` directory is present under `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess`, owned by `keyhelp:keyhelp`, and that the shell scripts are executable:

```bash
chown -R keyhelp:keyhelp /home/keyhelp/www/keyhelp/dashboard-layout
chmod 755 /home/keyhelp/www/keyhelp/dashboard-layout /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
chmod +x /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/install.sh \
         /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/uninstall.sh \
         /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/update-goaccess.sh \
         /home/keyhelp/www/keyhelp/dashboard-layout/goaccess/goaccess-lang-runner.sh
```

### Step 5: Run the Installer

Run `install.sh` as `root`. If no `*.conf` file exists yet, it prompts for your KeyHelp username and statistics domain and creates `<user>.conf` inside `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/`:

```bash
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
./install.sh
```

The installer automatically:
- Enables and generates the required UTF-8 locales in `/etc/locale.gen`.
- Creates `/var/lib/goaccess-db/<user>` with permissions for `<user>:www-data`.
- Installs `update-goaccess.sh` and `goaccess-lang-runner.sh` to `/usr/local/bin/`.
- Copies `gen-lang.php` into your statistics subdomain webroot (`OUT_DIR`).
- Installs and enables `goaccess-lang.path` and `goaccess-lang.service`.

### Step 6: Adjust Configuration & Add Additional Users (Optional)

Edit your generated `<user>.conf` in `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/` to exclude domains (such as `mail.example.com` or `stats.example.com` itself) or change the default language:

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
> **Supporting Multiple KeyHelp Users:** Copy `goaccess.conf.example` to `<seconduser>.conf` inside `/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/`, adjust `KH_USER` and `STATS_DOMAIN`, and re-run `./install.sh` so directories and `gen-lang.php` are provisioned for that user as well.

### Step 7: Generate Initial Reports & Set Up a Cronjob

Run the generator once manually to build the initial GoAccess database and HTML files:

```bash
/usr/local/bin/update-goaccess.sh
systemctl is-active goaccess-lang.path
```

Verify that HTML files were created in your statistics webroot:

```bash
ls -la /home/users/<KH_USER>/www/<STATS_DOMAIN>/*.html
```

To keep your statistics up to date automatically, add a root cronjob (e.g. every 15 minutes) via `crontab -e`:

```cron
*/15 * * * * /usr/local/bin/update-goaccess.sh >/dev/null 2>&1
```

### Step 8: Open & Use GoAccess in the Browser

1. Make sure you have an active session in your **KeyHelp** panel (so your browser holds a valid KeyHelp session cookie for CSRF-protected language switching).
2. Open your statistics subdomain in the browser by navigating directly to one of your generated domain reports:
   `https://stats.example.com/<your-domain.tld>.html`
3. Use the **left sidebar** (`Domains (A–Z)`) and the search input (`Domain suchen...`) to switch between all analyzed domains.
4. Use the **language dropdown** in the top-right corner of the sidebar to switch the report language. An overlay (`Generate... please wait`) appears while `systemd` regenerates all reports in the selected language, and the page reloads automatically once finished.

***

## Updating & Uninstalling

### Updating

Pull the latest changes as `keyhelp` and re-run `install.sh` as `root` to update `/usr/local/bin/` scripts, `gen-lang.php`, and `systemd` units (your local `*.conf` files are git-ignored and remain untouched):

```bash
su -s /bin/sh keyhelp -c "git -C /home/keyhelp/www/keyhelp/dashboard-layout pull"
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess && ./install.sh
```

### Uninstalling

To stop and remove the `systemd` units and helper scripts under `/usr/local/bin/`:

```bash
cd /home/keyhelp/www/keyhelp/dashboard-layout/goaccess
./uninstall.sh
```
