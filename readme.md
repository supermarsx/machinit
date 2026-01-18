![machinit banner](https://github.com/user-attachments/assets/4126f9e7-dc86-4024-b7c0-9ae04b3aeba5)

<br>
<br>

[![CI](https://img.shields.io/github/actions/workflow/status/supermarsx/machinit/.github/workflows/ci.yml?branch=main&style=flat-square)](https://github.com/supermarsx/machinit/actions/workflows/ci.yml)
[![GitHub stars](https://img.shields.io/github/stars/supermarsx/machinit?style=flat-square)](https://github.com/supermarsx/machinit/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/supermarsx/machinit?style=flat-square)](https://github.com/supermarsx/machinit/network/members)
[![GitHub watchers](https://img.shields.io/github/watchers/supermarsx/machinit?style=flat-square)](https://github.com/supermarsx/machinit/watchers)
[![Open issues](https://img.shields.io/github/issues/supermarsx/machinit?style=flat-square)](https://github.com/supermarsx/machinit/issues)
[![Made with Shell & Tears](https://img.shields.io/badge/made%20with-Shell%20%26%20Tears-ffa500?style=flat-square)](https://github.com/supermarsx/machinit)


# machinit — macOS bootstrap & dotfiles installer

> A curated macOS bootstrap and dotfiles installer designed for reproducible, opinionated developer setups. Includes a safe installer flow, shell aliases & functions, zsh completions, and a test harness to validate changes.

Key goals:
- reproducible machine setup for dev environments
- safe, audit-friendly defaults with a DRY_RUN (dry-run) mode
- curated CLI completions, aliases, and helper scripts for productivity

---

## Quick start

1. Clone the repo and run the installer:

```bash
git clone https://github.com/supermarsx/machinit.git
cd machinit
chmod +x install.sh
./install.sh
```

2. See what would change without applying anything:

```bash
./install.sh --dry-run
```

3. Customize `config.toml` before running for any machine-specific settings.

## CLI flags / options

The top-level installer `install.sh` exposes several useful command-line flags to control
behavior and limit the scope of operations (useful for automation or CI). A quick reference:

- `--dry-run` — Simulate actions without making changes (safe testing).
- `--update` — Self-update the repository (git pull) and exit.
- `--config <file>` — Use an alternate configuration TOML file to filter which scripts run.
- `--no-log` — Disable persistent logging to the `./logs/` directory.
- `--verbose` / `-v` — Enable verbose stdout (set -x) for troubleshooting.
- `--start-from <script>` — Resume execution starting at the specified script file name.
- `--run-only <N>` — Run only the 1-based indexed script N from `scripts/` and exit.
- `--restart-ui` — After a successful run, perform the final UI restart step (Dock/Finder/etc.).
- `--update-shell` — Only update `~/.aliases` and `~/.functions` then exit (runs `scripts/012_install_dotfiles.sh --only-shell`).
- `--reset-finder-view` — Remove per-folder `.DS_Store` files under the user's home and set Finder list-view defaults.
-- `--pin-sidebar` — Pin configured Finder sidebar items (Downloads / Projects) then exit. By default the installer uses the bundled finder_sidebar_editor implementation located at `scripts/lib/finder_sidebar_editor.py`.
	- `--pin-sidebar-use-mysides` — When used with `--pin-sidebar`, explicitly request that the installer use the `mysides` tool instead of the default finder_sidebar_editor.
- `--clear-logs` — Remove all files under `./logs/` and exit.
- `--resume-failure` — Resume a previously failed run using the script name recorded in `logs/last_failed`.
- `--exit` — Immediate no-op exit (used for testing/CI flows).
- `--computer-name <name>` — Set the computer name non-interactively (uses macOS scutil and defaults writes).
- `--help` / `-h` — Show short help for the installer.

Additionally some scripts accept their own flags. For example:

- `scripts/052_configure_finder_and_sidebar.sh --add-sidebar-only` — Add Finder sidebar items only and exit (useful when run directly or via `install.sh --pin-sidebar`).
-- `scripts/052_configure_finder_and_sidebar.sh --use-mysides` — Explicitly request the script use the `mysides` tool to perform pinning; by default the script prefers the bundled finder_sidebar_editor under `scripts/lib` and will not try `mysides` unless explicitly instructed.

finder_sidebar_editor integration (bundled)
-------------------------------
This repository includes a bundled, dependency-light finder_sidebar_editor
implementation under `scripts/lib/finder_sidebar_editor.py` which is used by
default by `scripts/052_configure_finder_and_sidebar.sh` and by the
top-level `install.sh --pin-sidebar` flow. This avoids external dependencies
and ensures predictable behavior across systems.

If you'd prefer to use an external `mysides` binary instead, invoke the
script or installer with the `--use-mysides` / `--pin-sidebar-use-mysides`
flags (the installer won't try `mysides` unless explicitly requested).

If you're interested in the original upstream project (robperc/FinderSidebarEditor),
you may still install it separately via pip if you want the fuller behavior:

Example:
```bash
python3 -m pip install "git+https://github.com/robperc/FinderSidebarEditor.git"
```

-- By default the repository uses the bundled `finder_sidebar_editor` under `scripts/lib`.
	If you'd prefer the older cli-based `mysides` path instead, invoke the script
	with `--use-mysides` or set the environment variable `USE_MYSIDES=1`. At the
	top-level installer use `--pin-sidebar-use-mysides` when invoking `--pin-sidebar`.

When the bundled finder_sidebar_editor cannot be used (for example, python3 is
not found) the script falls back to AppleScript UI automation. `mysides` is
only attempted when explicitly requested with `--use-mysides`.
- `scripts/011_check_aliases_functions_conflicts.sh --abort-on-conflict` — Exit non-zero if conflicts detected (used by `scripts/012_install_dotfiles.sh` by default; the top-level installer bypasses aborts during a full run).

Use `./install.sh --dry-run` to test these behaviors safely before running on a live machine.


## What this repo contains (short)

- `install.sh` — top-level orchestrator (supports flags like `--dry-run`, `--resume-failure`, `--clear-logs`).
- `scripts/` — many ordered scripts to install packages, configure system settings, and apply UI customizations.
- `assets/` — dotfiles, zsh completion files, themes, and templates.
- `dev_scripts/` — test, fetcher, and maintenance helpers (fetch completions, run the test harness, linting helpers).
- `dev_scripts/generate_inventory.py` — generates a current list of aliases, functions, completions, install targets and defaults into `docs/inventory.md` (run locally to refresh).
- `tests/` — local test harness that validates non-destructive behavior (safely using DRY_RUN).

---

## Global gitignore

This repository provides a recommended global gitignore at `assets/.gitignore_global`. It is intended as a sensible default for macOS developer machines and includes common ignores for:

- OS files and caches (macOS)
- Editors / IDEs (VS Code, JetBrains/IntelliJ/Android Studio)
- Language/tool build artifacts (Node.js, Python, Rust, Go, Java/Gradle, Ruby/Rails, PHP/Composer)
- Mobile/tooling (Android/Kotlin, Xcode/iOS)
- Containers / infra (Docker, Terraform)
- Environment and secret files (e.g. `.env`, private keys)

How to use it locally as your global excludes file:

```bash
cp assets/.gitignore_global ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global
```

Notes:
- The file is meant to be a convenient starting point — review and customize it for your workflow before applying globally.
- It intentionally does not ignore dependency lockfiles (e.g. `package-lock.json`, `Gemfile.lock`, `Cargo.lock`) since those are commonly committed for reproducible builds.
- Contributions and additions are welcome; keep unrelated repo-specific ignores out of the global file.

## Functions

The following helper functions are provided in `assets/.functions`. Source that file into your shell (`source /path/to/machinit/assets/.functions`) to make these available in your interactive session.

- `mkd` — create a new directory (with parents) and immediately `cd` into it.
- `cdf` — change working directory to the top-most Finder window location (macOS Finder integration).
- `targz` — create a `.tar.gz` archive using `zopfli`, `pigz` or `gzip` (chooses best available compressor).
- `fs` — show size of a file or total size of a directory in a human-readable form (portable `du` wrapper).
- `diff` — use Git’s colored diff when available (`git diff --no-index --color-words`).
- `dataurl` — produce a data URL (base64) from a file; sets proper mime-type for text files.
- `server` — start a simple HTTP server (Python) from the current directory and open it in a browser; enables CORS.
- `gz` — compare original and gzipped file sizes and print ratio.
- `digga` — run `dig` with useful flags to show concise DNS answers.
- `getcertnames` — print the Common Name and Subject Alternative Names from an HTTPS certificate for a domain.
- `o` — `open` wrapper: `o` opens the current directory if called without args, otherwise opens its arguments.
- `tre` — enhanced `tree` alias: show hidden files, color, ignore `.git` and `node_modules`, view with `less`.
- `generate_git_key` — interactive helper to generate a new SSH key (ed25519), add it to the ssh-agent/keychain, and instruct how to add the public key to GitHub.
- `myaliases` — print a formatted table of aliases and functions (supports `--aliases`, `--functions`, `--all`).
- `findPid` — helper to find process IDs by process name/regex (uses `lsof -t -c`).
- `recent` — `cd` to the most recently modified project directory under `~/Projects` (supports indexing and name patterns).
- `ll` — robust `ls` wrapper that prefers GNU `ls`/`gls` but falls back safely for BSD systems.
- `myip` — robust public IP lookup with multiple service fallbacks and optional IPv6 support.


These functions are written to be safe for interactive shells (bash/zsh). If you rely on shell-specific features, consider sourcing the file from the appropriate rc file (e.g. `~/.zshrc` or `~/.bashrc`).

## Aliases

The following aliases are provided in `assets/.aliases` for quick command-line shortcuts.

Note: these aliases live in `assets/.aliases`. Source this file from your shell rc to enable them (for example, add `source /path/to/machinit/assets/.aliases` to `~/.zshrc` or `~/.bashrc`). The file is intended to be compatible with both bash and zsh; do not execute it directly because aliases defined in a subshell will not persist in your interactive shell.

- `bup` — `brew update && brew upgrade && brew cleanup` — update Homebrew, upgrade packages, cleanup
- `reloaddns` — `dscacheutil -flushcache && sudo killall -HUP mDNSResponder` — flush macOS DNS cache and restart `mDNSResponder` (requires `sudo`)
- `dnsreload` — `dscacheutil -flushcache && sudo killall -HUP mDNSResponder` — flush macOS DNS cache and restart `mDNSResponder` (requires `sudo`)
- `timestamp` — `date +%s` — print current epoch timestamp (seconds since UNIX epoch)
- `jsrefresh` — `rm -rf node_modules/ package-lock.json && npm install` — remove node deps and reinstall

Navigation:
- `..` — `cd ..` — go up one directory
- `...` — `cd ../../..` — go up two levels
- `....` — `cd ../../../../` — go up three levels
- `.....` — `cd ../../../../` — go up deeper (lenient duplicate)
- `cd..` — `cd ..` — alternate form to go up one
- `~` — `cd ~` — go to home directory
- `~~` — `cd -` — switch to previous working directory (use `~~` to go to the previous dir)

Shortcuts:
- `c` — `clear` — clear terminal screen
- `h` — `history` — display shell history
 

Zsh / config editors:
- `zshconf` — `nano ~/.zshrc` — open zsh configuration for quick edits

Project navigation:
- `projects` — `cd ~/Projects` — change to `~/Projects`
- `repos` — `cd ~/Projects` — same as `projects`

Common folders:
- `docs` — `cd ~/Documents` — go to `~/Documents`
- `downloads` — `cd ~/Downloads` — go to `~/Downloads`
- `dl` — `cd ~/Downloads` — short form to go to `~/Downloads`

Helpers:
- `qfind` — `find . -name` — find files by name in current dir
- `lsock` — `sudo lsof -i -P` — list network sockets (requires sudo)

Network:
- `ping_test` — `ping 1.1.1.1` — quick ping to Cloudflare DNS
- `localip` — `ipconfig getifaddr en0` — show local IP address for primary interface (macOS)

NPM shortcuts:
- `ni` — `npm install` — shorthand to install npm dependencies
- `nps` — `npm start` — shorthand to run `npm start`

Diagnostics & fun:
- `wtf` — `dmesg | tail` — show last kernel messages
- `up` — `echo "Time is an illusion."; uptime` — prints a fun message then shows uptime

Clipboard emoticons:
- `shrug` — `echo "¯\\_(ツ)_/¯" | pbcopy` — copy shrug emoticon to clipboard
- `tableflip` — `echo "(╯°□°）╯︵ ┻━┻" | pbcopy` — copy tableflip emoticon to clipboard
- `fix` — `echo "┬─┬ ノ( ゜-゜ノ)" | pbcopy` — copy fix emoticon to clipboard

Utilities:
- `entropy` — `openssl rand -base64 64` — generate 64 bytes of base64 randomness
- `void` — `>/dev/null 2>&1` — shortcut for discarding output
- `fractal` — `open -a Terminal .` — open current folder in Terminal
- `eldritchterror` — `open https://en.wikipedia.org/wiki/Heat_death_of_the_universe` — open doom article

System:
- `path` — `echo -e ${PATH//:/\\n}` — print PATH entries one-per-line (uses `${PATH//:/\\n}` which is supported in bash and zsh)
- `cpu` — `top -o cpu` — show top processes by CPU
- `mem` — `top -o rsize` — show top processes by memory usage (resident size)

- `afk` — `pmset displaysleepnow` — put display to sleep / lock screen
- `wifi_pass` — `security find-generic-password -wa` — retrieve WiFi password from keychain (append SSID)
 
## Completions

The `assets/completions/` directory contains curated zsh completion scripts included with these dotfiles. Install or source them into your shell to get improved tab completion for many common commands.

Included completion scripts (filename -> purpose):

- `_git` — Git CLI: subcommands and options completion.
- `_npm` — npm: curated npm subcommands and package.json helpers.
- `_node` — Node.js: official node CLI completion.
- `_copilot` — Copilot CLI: GitHub/AWS Copilot command completion.
- `_nvm` — Node Version Manager: install/use/list completions.
- `_npx` — npx: run binaries from node_modules with completion.
- `_yarn` — yarn: common yarn commands.
- `_cargo` — Cargo (Rust): build/test/run/etc. completions.
- `_rustc` — rustc: compiler flags and options.
- `_clang` / `_clang++` — Clang/Clang++: compiler options.
- `_gcc` / `_g++` — GCC/G++: compiler and linker flags.
- `_cmake` — CMake: generator and target completions.
- `_gnumake` — GNU make: common targets and options.
- `_vcpkg` — vcpkg: package manager completions for C/C++.
- `_black` / `_flake8` — Python tooling (formatter/linter) completions.
- `_grep` / `_egrep` / `_fgrep` — grep-family completions (search tools).
- `_rg` / `_ripgrep` — ripgrep: fast recursive search completion.
- `_ssh` — ssh client completions (hosts, options).
- `_curl` — curl: URL/option completions and common flags.
- `_wget` — wget: download utility completions.
- `_tar` — tar: archive operations and options.
- `_rsync` — rsync: sync options and remote/target completions.
- `_ip` / `_ipconfig` — network tools (ip/ipconfig) completions.
- `_ping` / `_dig` / `_nslookup` — DNS and network diagnostic completions.
- `_df` / `_du` — disk utilities completions.
- `_cat` / `_dd` / `_hexdump` — raw file utilities completions.
- `_code` / `_gh` / `_github` / `_opencode` / `_codex` — editor & GitHub/CLI completions.
- `_cron` / `_crontab` — cron scheduling helpers and crontab completions.
- `_dockutil` — macOS Dock utility completions.
- `_nvram` / `_ifconfig` — macOS system utilities completions.

Note: Some completions are auto-generated or derived from upstream sources; where available the scripts prefer a tool's native completion output. For the full list, see the `assets/completions/` folder.

## Installed Apps

These are the GUI apps and developer tools the installer can install (via Homebrew Casks or other helpers). Each entry references the script that performs the install in `scripts/`.

### Editors & IDEs

- `Visual Studio Code` — popular, extensible code editor with many extensions. (`scripts/021_install_vscode.sh`)
- `OpenCode` — a lightweight code editor/tooling package installed via Homebrew. (`scripts/023_install_opencode.sh`)
- `Mark Text` — an open-source WYSIWYG Markdown editor for writing and previewing Markdown. (`scripts/010_install_apps.sh`)

### Terminal & Shells

- `iTerm2` — a feature-rich terminal emulator for macOS with profiles, tabs and split panes. (`scripts/010_install_apps.sh`)
- `PowerShell` — Microsoft's cross-platform shell and scripting environment. (`scripts/007_install_powershell.sh`)

### Browsers & Web Tools

- `Google Chrome` — the Chromium-based web browser. (`scripts/028_install_google_chrome.sh`)
- `Chrome DevTools MCP` — Chrome DevTools helper/utility installed for browser development workflows. (`scripts/027_install_chrome_devtools_mcp.sh`)
- `Firefox` — the Mozilla Firefox web browser (configurable via policies.json for extensions). (`scripts/020_install_firefox.sh`)

### Office & Productivity

- `Microsoft Word` — word processing application from Microsoft Office. (`scripts/035_install_microsoft_word.sh`)
- `Microsoft Excel` — spreadsheet application from Microsoft Office. (`scripts/032_install_microsoft_excel.sh`)
- `Microsoft PowerPoint` — presentation application from Microsoft Office. (`scripts/034_install_microsoft_powerpoint.sh`)
- `Microsoft Outlook` — email and calendar client from Microsoft Office. (`scripts/033_install_microsoft_outlook.sh`)
- `Standard Notes` — an encrypted note-taking application focused on privacy and sync. (`scripts/010_install_apps.sh`)
- `Adobe Acrobat Reader` — a PDF reader for viewing and annotating PDFs. (`scripts/036_install_adobe_reader.sh`)

### Communication

- `Beeper` — chat/IM aggregation client that can bridge multiple services. (`scripts/024_install_beeper.sh`)
- `GitHub Desktop` — graphical Git client for GitHub workflows. (`scripts/025_install_github_desktop.sh`)

### Dev Tooling & Runtimes

- `nvm (Node Version Manager)` — manage multiple Node.js versions per-user. (`scripts/004_install_nvm.sh`)
- `Rust (rustup)` — installs the Rust toolchain using `rustup` (compiler, Cargo, toolchains). (`scripts/005_install_rust.sh`)
- `vcpkg` — C/C++ package manager for native dependencies. (`scripts/006_install_vcpkg.sh`)
- `OpenAI Codex CLI` — CLI tooling for interacting with the Codex/AI helper (where available). (`scripts/022_install_codex.sh`)

### Networking & Security

- `OpenVPN Connect` — official OpenVPN client for connecting to OpenVPN servers. (`scripts/037_install_openvpn.sh`)

### Security & Password managers

- `Bitwarden` — a secure cloud-backed password manager and vault (desktop client). (`scripts/030_install_bitwarden.sh`)
- `KeePassXC` — an offline, open-source cross-platform password manager for local vaults. (`scripts/026_install_keepassxc.sh`)

### Sync & Storage

- `Nextcloud` — desktop sync client for Nextcloud file sync services. (`scripts/029_install_nextcloud.sh`)

### Fonts & System

- `Fantasque Sans Mono` — a bundled monospace font installed for development/terminal use. (`scripts/009_install_fonts.sh`)


## System tweaks & defaults (summary)

This installer applies a curated set of macOS preference tweaks and system settings across multiple scripts. Most changes are DRY_RUN-safe and are applied using `defaults write`, `pmset`, `nvram`, `dockutil`, or the helper `set_user_default` to target per-user domains. Changes that require elevated privileges write to `/Library/Preferences` or are run with `sudo`.

High-level categories of tweaks applied by the installer:

- **UI / Appearance:** enable Dark Mode, reduce transparency, disable many window animations, set system accent/highlight values, show battery percentage.
- **Dock & Mission Control:** adjust icon size, enable auto-hide with no delay/animation, minimize-to-application, hide recent apps, speed up Mission Control animations, pin curated apps and folder stacks (via `dockutil`).
- **Finder & Sidebar:** show all filename extensions, enable status/path bars, default to List view, prevent `.DS_Store` on network/USB volumes, configure sidebar items and default new-window location, unhide `~/Library` and `/Volumes`.
- **Safari:** privacy/security changes (disable search suggestions, show full URL, enable Develop menu, disable AutoFill, disable Java/plugins, block pop-ups), clear Favorites/History when requested, and postpone Safari recommendation notices.
- **Spotlight:** restrict indexing to Applications only and disable web/Siri suggestions and Spotlight query suggestions.
- **Power & Performance:** SSD-friendly settings (hibernatemode, remove sleepimage), enable HiDPI, pmset tweaks (lid wake, display sleep, low power mode), and disable some background agents where possible.
- **Input devices & keyboard:** disable swipe navigation, adjust keyboard illumination, map Fn to Emoji & Symbols, disable automatic capitalization/quotes/period substitution and auto-correct.
- **Security & Privacy:** disable crash reporting/auto-submit, enable Application Firewall + stealth/block-all, disable AirDrop/AirPlay Receiver, and disable quarantine prompts for Brew-installed apps where configured.
- **System apps & utilities:** prevent Photos auto-open on plug, Time Machine behavior tweaks, Activity Monitor showing all processes, TextEdit defaults (UTF-8), and App Store/Software Update preferences.
- **Terminal & iTerm2:** import themes, set Terminal encoding and secure keyboard entry, and inject a theme prompt block into `~/.zshrc`.

Notes:

- Many preference writes are best-effort and may be ignored by newer macOS versions, MDM profiles, or TCC restrictions. Where applicable, scripts check for Full Disk Access or use `execute_as_user` to write per-user preferences.
- Restarts of Finder/Dock/SystemUIServer are deferred to `scripts/999_restart_apps.sh` so changes are applied together at the end of a full run.

## Firefox extensions

The installer can configure Firefox via a `policies.json` file to auto-install curated extensions. The current curated list (written by `scripts/020_configure_firefox_policies.sh`) is:

- `uBlock Origin` — content blocker for ads and trackers.
- `Violentmonkey` — userscript manager for custom client-side scripts.
- `Stylus` — site-specific CSS manager for custom styling.
- `FoxyProxy Standard` — advanced proxy management helper.
- `Dark Reader` — per-site dark mode for websites.
- `ColorZilla` — eyedropper and color utilities for web design.
- `Bitwarden` — password manager and vault integration.
- `Clear Cache` — quick cache clearing helper for Firefox.

These are installed by `scripts/020_configure_firefox_policies.sh` into Firefox's `distribution/policies.json` (requires Full Disk Access to write into the app bundle path when run locally).

## Visual Studio Code extensions

The installer installs a small curated list of VS Code extensions (see `scripts/031_install_vscode_extensions.sh`). Current extensions include:

- `openai.chatgpt` — OpenAI / ChatGPT integration for editor assistance.
- `dbaeumer.vscode-eslint` — ESLint integration for JavaScript/TypeScript linting.
- `github.vscode-github-actions` — GitHub Actions workflow tooling.
- `github.copilot-chat` — GitHub Copilot Chat extension.
- `davidanson.vscode-markdownlint` — Markdown linting rules and validation.
- `christian-kohler.npm-intellisense` — npm package auto-imports for JS/TS.
- `timonwong.shellcheck` — ShellCheck integration for shell script linting.
- `rooveterinaryinc.roo-cline` — curated tooling (installed when available).
- `chadbaileyvh.oled-pure-black---vscode` — dark OLED-friendly theme.
- `streetsidesoftware.code-spell-checker` — spelling diagnostics for code and docs.

VS Code extensions are installed by `scripts/031_install_vscode_extensions.sh` using the `code` CLI when available; the script is DRY_RUN-aware and will skip installation in CI/dry-run modes.

## Test harness & CI

We validate changes using the test harness `dev_scripts/test.sh`. This script discovers tests under `tests/` and runs them in a safe manner.

Common commands:

```bash
# Run all tests (shell + python where applicable)
./dev_scripts/test.sh

# Run only completion-related tests and print output
./dev_scripts/test.sh --pattern completions --verbose

# Use the pytest mode for python tests when helpful
./dev_scripts/test.sh --pytest
```

Local development checklist:

1. Make edits to completions, scripts, dotfiles
2. Run linting: `./dev_scripts/lint.sh`
3. Run focused tests: `./dev_scripts/test.sh --pattern completions --verbose`
4. If everything passes, commit and open a PR

CI note: the repository has a GitHub Actions pipeline that runs these tests for PRs and pushes — keep changes test-friendly and DRY_RUN-safe.

---

## Contributing

We welcome contributions — typical flows:

1. Fork and create topic branch.
2. Make small, well-scoped changes (completions, scripts, docs, tests).
3. Add/adjust tests in `tests/` to exercise changes, prefer DRY_RUN-friendly assertions.
4. Run the test harness locally and ensure green CI.

Developer tips:

- Keep completions conservative and offline-friendly (avoid network calls during shell completion evaluation).
- Use `dev_scripts/fetch_completions.py` to fetch or regenerate helpful completions.
- If replacing an existing completion file, keep a backup copy or prefer `.generated` suffix until changes are validated.

---

## Security & Notes

This installer makes system-level changes and should be audited carefully before running. Use `--dry-run` and test on disposable machines or VMs if in doubt.

---

## License

MIT — see `license.md`.

---

If you'd like, I can also generate:
- a single cheat-sheet markdown (commands + flags) for tools we polished (e.g., Copilot, Codex, OpenCode), or
- machine-readable JSON/YAML specifications for completions (useful for generating richer completions).
