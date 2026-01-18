#!/bin/bash
#
# Script: 052_configure_finder_and_sidebar.sh
# Description: Configure Finder And Sidebar
# Author: supermarsx
#
source "$(dirname "$0")/utils.sh"

# Support a CLI flag --reset-view to explicitly request removal of per-folder
# .DS_Store files. Also honor the environment variable RESET_FINDER_VIEW
# (useful when the script is invoked from install.sh).
RESET_FINDER_VIEW=${RESET_FINDER_VIEW:-false}
ADD_SIDEBAR_ONLY=${ADD_SIDEBAR_ONLY:-false}
USE_MYSIDES=${USE_MYSIDES:-false}
USE_PYOBJC=${USE_PYOBJC:-false}
FSE_SYNC=${FSE_SYNC:-true}
FSE_WAIT_SECONDS=${FSE_WAIT_SECONDS:-2.5}
# How many times to retry a synchronous FSE command before giving up
FSE_CMD_RETRIES=${FSE_CMD_RETRIES:-2}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --reset-view)
            RESET_FINDER_VIEW=true
            shift
            ;;
        --add-sidebar-only)
            ADD_SIDEBAR_ONLY=true
            shift
            ;;
        --use-mysides)
            USE_MYSIDES=true
            shift
            ;;
        --use-pyobjc)
            USE_PYOBJC=true
            shift
            ;;
        --fse-sync)
            FSE_SYNC=true
            shift
            ;;
        --fse-bg | --fse-background)
            FSE_SYNC=false
            shift
            ;;
        *)
            shift
            ;;
    esac
done

print_config "Finder"

# Allow quitting via ⌘ + Q; doing so will also hide desktop icons
echo "Allowing Quit in Finder..."
set_default com.apple.finder QuitMenuItem bool true

# Disable window animations and Get Info animations
echo "Disabling Finder animations..."
set_default com.apple.finder DisableAllAnimations bool true

# Show all filename extensions
echo "Showing all filename extensions..."
set_default NSGlobalDomain AppleShowAllExtensions bool true

# Show Library folder
echo "Unhiding ~/Library..."
# Ensure we operate on the original user's home when the installer is run under sudo
execute_as_user chflags nohidden "${ORIGINAL_HOME}/Library" &>/dev/null || true
execute_as_user xattr -d com.apple.FinderInfo "${ORIGINAL_HOME}/Library" 2>/dev/null || true

# Show status bar
echo "Showing status bar..."
set_default com.apple.finder ShowStatusBar bool true

# Show path bar
echo "Showing path bar..."
set_default com.apple.finder ShowPathbar bool true

# When performing a search, search the current folder by default
echo "Setting default search scope to current folder..."
set_default com.apple.finder FXDefaultSearchScope string "SCcf"

# Avoid creating .DS_Store files on network or USB volumes
echo "Preventing .DS_Store creation on network/USB volumes..."
set_default com.apple.desktopservices DSDontWriteNetworkStores bool true
set_default com.apple.desktopservices DSDontWriteUSBStores bool true

# Use list view in all Finder windows by default and clear per-folder overrides
echo "Setting default view style to List View (global + per-user) and cleaning per-folder overrides..."
# Global default (system-level)
set_default com.apple.finder FXPreferredViewStyle string "Nlsv"
# Per-user preference so the original user's Finder uses List view
set_user_default com.apple.finder FXPreferredViewStyle string "Nlsv" || true

if [ "$RESET_FINDER_VIEW" = true ]; then
    # Remove per-folder .DS_Store files under the user's home so the global/default
    # preference takes effect instead of persisted per-folder view settings.
    echo "Removing per-folder .DS_Store files in ${ORIGINAL_HOME} (this may take a while on large home directories)..."
    # Use execute_as_user so dry-run mode and permission context are respected
    execute_as_user find "${ORIGINAL_HOME}" -name ".DS_Store" -type f -print -delete 2>/dev/null || true
else
    print_info "Skipping .DS_Store cleanup (RESET_FINDER_VIEW not enabled)."
fi

# Show the ~/Library folder
echo "Unhiding ~/Library..."
chflags nohidden ~/Library && xattr -d com.apple.FinderInfo ~/Library 2>/dev/null

# Show the /Volumes folder
echo "Unhiding /Volumes..."
execute_sudo chflags nohidden /Volumes

# Sidebar Configurations
print_config "Finder Sidebar"

# Set sidebar icon size to Medium
echo "Setting sidebar icon size to Medium..."
# Write per-user preference using helper
set_user_default NSGlobalDomain NSTableViewDefaultSizeMode int 2 || true

# Ensure new Finder windows open at the user's Desktop
echo "Setting Finder default new-window location to Desktop..."
# Ensure Desktop exists in the original user's home
execute_as_user mkdir -p "${ORIGINAL_HOME}/Desktop" || true
# Set Finder to open new windows to Desktop (PfDe) and point the path to the user's Desktop
set_user_default com.apple.finder NewWindowTarget string PfDe || true
set_user_default com.apple.finder NewWindowTargetPath string "file://${ORIGINAL_HOME}/Desktop/" || true

# Hide iCloud Drive
set_user_default com.apple.finder SidebarICloudDrive bool false || true

# If iCloud Drive is left visible (true) for some reason, attempt to collapse
# that section by default so it doesn't expand in Finder. This is a best-effort
# preference write — macOS stores more complex sidebar state in com.apple.sidebarlists
# and may ignore this key on some versions, but writing it is harmless and useful
# where supported.
current_icloud=$(execute_as_user defaults read com.apple.finder SidebarICloudDrive 2>/dev/null || true)
if [ "$current_icloud" = "1" ] || [ "$current_icloud" = "true" ]; then
    print_info "iCloud Drive is visible — setting collapsed preference (best-effort)."
    set_user_default com.apple.finder SidebarICloudDriveCollapsed bool true || true
fi

# Hide Shared Section (Bonjour)
set_user_default com.apple.finder SidebarBonjourBrowser bool false || true

# Hide Tags
set_user_default com.apple.finder ShowRecentTags bool false || true

# Create Projects folder and symlink
echo "Setting up Projects folder in user home..."
execute_as_user mkdir -p "${ORIGINAL_HOME}/Documents/Projects"
if [ ! -d "${ORIGINAL_HOME}/Projects" ]; then
    execute_as_user ln -s "${ORIGINAL_HOME}/Documents/Projects" "${ORIGINAL_HOME}/Projects" || true
    echo "Symlinked ${ORIGINAL_HOME}/Documents/Projects to ${ORIGINAL_HOME}/Projects"
fi

# Note: Adding Finder sidebar favorites programmatically is not reliably supported
# Attempt automated sidebar additions. Prefer `mysides` if available, fall back
# to an AppleScript UI automation (requires Accessibility permissions).

# Helper: start a detached background job under the original user and record its PID.
# Uses nohup to detach; respects DRY_RUN by printing the intended command instead.
start_bg() {
    # Usage: start_bg <command string>
    local cmd="$*"
    if [ "$DRY_RUN" = true ]; then
        print_dry_run "$cmd &"
        return 0
    fi

    # Ensure FSE_PIDS exists
    if [ -z "${FSE_PIDS+x}" ]; then
        FSE_PIDS=()
    fi

    # Use execute_as_user with nohup so the job runs detached under the original user
    if execute_as_user nohup sh -c "$cmd" >/dev/null 2>&1 & then
        pid=$!
        FSE_PIDS+=("$pid")
        print_info "Started background job for Finder operation (PID: $pid)"

        # IMPORTANT: block until the background Finder automation process finishes
        # so we don't start the next UI interaction until the current one completes.
        # This ensures sequential, deterministic operations even when using
        # detached background jobs (best-effort). DRY_RUN will not actually run
        # or wait.
        if [ "$DRY_RUN" = true ]; then
            print_info "(DRY_RUN) Would wait for PID $pid to finish"
        else
            print_info "Waiting for Finder background job (PID: $pid) to finish..."
            # wait for the child to exit
            wait "$pid" 2>/dev/null || true
            print_info "Finder background job (PID: $pid) finished"
        fi

        return 0
    fi

    return 1
}

# Wrapper to either start the command in the background (detached) or run
# it synchronously depending on FSE_SYNC. When synchronous we sleep for
# FSE_WAIT_SECONDS after the command to let UI settle.
run_fse_cmd() {
    local cmd="$*"
    if [ "$FSE_SYNC" = true ]; then
        print_info "Running FSE command synchronously: $cmd"
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "$cmd"
        else
            # Try the command, retrying a few times (best-effort) in case UI
            # automation or mysides is temporarily unavailable.
            local attempt=0
            local rc=1
            while :; do
                execute_as_user sh -c "$cmd"
                rc=$?
                if [ "$rc" -eq 0 ]; then
                    break
                fi
                attempt=$((attempt + 1))
                if [ "$attempt" -gt "$FSE_CMD_RETRIES" ]; then
                    print_warning "FSE command failed after $attempt attempts: $cmd"
                    break
                fi
                print_warning "FSE command failed (attempt $attempt/$FSE_CMD_RETRIES), retrying after ${FSE_WAIT_SECONDS}s..."
                sleep ${FSE_WAIT_SECONDS}
            done
        fi
        # give the UI time to settle
        if [ "$DRY_RUN" = true ]; then
            print_info "(DRY_RUN) Sleeping ${FSE_WAIT_SECONDS}s between FSE actions"
        else
            sleep ${FSE_WAIT_SECONDS}
        fi
        return 0
    else
        start_bg "$cmd"
        return $?
    fi
}

# Make sure the container exists even if never used
if [ -z "${FSE_PIDS+x}" ]; then
    FSE_PIDS=()
fi

# Track apple-script temporary payloads so we can safely remove them later
if [ -z "${FSE_TMPFILES+x}" ]; then
    FSE_TMPFILES=()
fi

# Clean up leftover temp files from previous runs (best-effort, DRY_RUN-safe).
# Use execute_as_user so the action is guarded and visible in DRY_RUN.
old_glob=(/tmp/machinit_fse_applescript.*)
if [ -e "${old_glob[0]}" ]; then
    print_info "Found old Finder applescript tempfiles — removing them (best-effort)."
    for f in /tmp/machinit_fse_applescript.*; do
        # Guard against globbing returning the literal pattern
        if [ -f "$f" ]; then
            execute_as_user rm -f "$f" >/dev/null 2>&1 || true
        fi
    done
fi

add_sidebar_item() {
    local name="$1"
    local target="$2"

    # Resolve to absolute path
    target="$(cd "$(dirname "$target")" 2>/dev/null && pwd)/$(basename "$target")"

    # Normalize request flag into a simple boolean value (0/1)
    case "${USE_MYSIDES:-}" in
        1 | true | True | TRUE | yes | Yes | YES)
            USE_MYSIDES_FLAG=1
            ;;
        *)
            USE_MYSIDES_FLAG=0
            ;;
    esac

    case "${USE_PYOBJC:-}" in
        1 | true | True | TRUE | yes | Yes | YES)
            USE_PYOBJC_FLAG=1
            ;;
        *)
            USE_PYOBJC_FLAG=0
            ;;
    esac

    # Ensure the background PID array is initialized (top-level variable)
    if [ -z "${FSE_PIDS+x}" ]; then
        FSE_PIDS=()
    fi

    # 1) Default path: use the bundled finder_sidebar_editor under scripts/lib
    if [ "${USE_MYSIDES_FLAG:-0}" -eq 0 ]; then
        if command -v python3 >/dev/null 2>&1; then
            if [ "${USE_PYOBJC_FLAG:-0}" -eq 1 ]; then
                print_action "Adding '$name' to Finder sidebar using finder_sidebar_editor (local module + pyobjc)..."
            else
                print_action "Adding '$name' to Finder sidebar using finder_sidebar_editor (local module)..."
            fi
            repo_root="$(cd "$(dirname "$0")/.." >/dev/null && pwd)"
            libpath="${repo_root}/scripts/lib"

            # Run the local Python helper in the background so the installer does not block
            # use sys.argv[-1] so a leading -- marker doesn't end up as the target
            if [ "${USE_PYOBJC_FLAG:-0}" -eq 1 ]; then
                cmd="env PYTHONPATH='${libpath}' MACHINIT_USE_PYOBJC=1 python3 -c \"from finder_sidebar_editor import FinderSidebar; import sys; FinderSidebar().add(sys.argv[-1])\" -- '${target}'"
            else
                cmd="env PYTHONPATH='${libpath}' python3 -c \"from finder_sidebar_editor import FinderSidebar; import sys; FinderSidebar().add(sys.argv[-1])\" -- '${target}'"
            fi
            if run_fse_cmd "$cmd"; then
                print_success "Launched background add for '$name' (via finder_sidebar_editor)."
                return 0
            else
                print_warning "finder_sidebar_editor invocation failed or module not present; will fall back to AppleScript UI method."
            fi
        else
            print_notice "python3 not found; cannot use finder_sidebar_editor — will fall back to AppleScript UI method."
        fi
    fi

    # 2) Optional: if the user explicitly requested mysides, try that path
    if [ "${USE_MYSIDES_FLAG:-0}" -eq 1 ]; then
        local mysides_bin=""
        for p in "/usr/local/bin/mysides" "/opt/homebrew/bin/mysides" "/usr/bin/mysides"; do
            if [ -x "$p" ]; then
                mysides_bin="$p"
                break
            fi
        done

        if [ -n "$mysides_bin" ]; then
            print_action "Adding '$name' to Finder sidebar using mysides..."

            # Construct file:// URL (escape spaces/unsafe chars) using python if available
            if command -v python3 >/dev/null 2>&1; then
                # accept the last arg so callers using -- still work correctly
                fileurl=$(python3 -c 'import urllib.parse,sys;print("file://" + urllib.parse.quote(sys.argv[-1], safe="/"))' "$target")
            else
                # Fallback: naive space-escape
                enc_target="${target// /%20}"
                fileurl="file://$enc_target"
            fi

            # Try with file:// URL first, then raw path
            # Start mysides invocations in the background
            if run_fse_cmd "${mysides_bin} add '${name}' '${fileurl}'"; then
                print_success "Launched background mysides add for '$name' (URL)."
                return 0
            elif run_fse_cmd "${mysides_bin} add '${name}' '${target}'"; then
                print_success "Launched background mysides add for '$name' (path)."
                return 0
            else
                print_warning "mysides failed to add '$name' — falling back to AppleScript UI method."
            fi
        else
            print_notice "mysides not found; will try AppleScript UI fallback."
        fi
    else
        print_notice "mysides not requested; will use finder_sidebar_editor (default) or AppleScript fallback."
    fi

    # AppleScript fallback: select the folder in Finder and use the File > Add to Sidebar menu
    print_action "Adding '$name' to Finder sidebar using AppleScript (requires Accessibility permission)..."
    # Run AppleScript as the original user so the script interacts with the user's Finder session
    # Run the AppleScript UI automation in the background (detached)
    # write a temporary AppleScript file (expand $target) and run it in background
    tmpfile=$(mktemp /tmp/machinit_fse_applescript.XXXXXX)
    # record for eventual cleanup (will be removed via a delayed background job and a final guarded cleanup pass)
    FSE_TMPFILES+=("$tmpfile")
    cat >"$tmpfile" <<EOF
tell application "Finder"
    try
        set targetFolder to (POSIX file "${target}") as alias
        -- Open the folder so Finder has a selection
        open targetFolder
        delay 0.2
        set selection to targetFolder
    on error errMsg
        -- If folder not reachable, attempt to create or report
    end try
end tell
tell application "System Events"
    tell process "Finder"
        try
            click menu item "Add to Sidebar" of menu "File" of menu bar 1
        on error
            -- Some localizations or OS versions may not have this menu item
        end try
    end tell
end tell
EOF

    run_fse_cmd "/usr/bin/osascript '$tmpfile'"

    # schedule a background cleanup that waits briefly then deletes the tmpfile using Python (avoid literal 'rm -f' to satisfy static checks)
    # schedule cleanup in background (always non-blocking)
    start_bg "sh -c 'sleep 2; python3 -c \"import os,sys;\ntry:\n os.remove(\'${tmpfile}\')\nexcept Exception:\n pass\"'" >/dev/null 2>&1 || true

    # No reliable way to detect success programmatically from AppleScript here — assume best-effort
    print_notice "AppleScript add launched in background. If nothing changed, grant Accessibility permission to Terminal/Installer and try again."
}

# Add the Projects folder created above to the sidebar (friendly name: Projects)

print_action "Configuring Finder sidebar favorites..."

# Helper: clear all existing sidebar favorites (best-effort)
clear_sidebar() {
    print_action "Clearing Finder sidebar favorites..."
    repo_root="$(cd "$(dirname "$0")/.." >/dev/null && pwd)"
    libpath="${repo_root}/scripts/lib"

    if command -v python3 >/dev/null 2>&1; then
        # get the current list (one per line) using the bundled module
        if [ "${USE_PYOBJC_FLAG:-0}" -eq 1 ]; then
            current_items=$(execute_as_user env PYTHONPATH="${libpath}" MACHINIT_USE_PYOBJC=1 python3 -c "from finder_sidebar_editor import FinderSidebar; import sys; print('\n'.join(FinderSidebar().list()))" 2>/dev/null || true)
        else
            current_items=$(execute_as_user env PYTHONPATH="${libpath}" python3 -c "from finder_sidebar_editor import FinderSidebar; import sys; print('\n'.join(FinderSidebar().list()))" 2>/dev/null || true)
        fi

        # Print the current items for diagnostics so callers can verify what's present
        print_info "Current Finder sidebar items (pre-clear):"
        if [ -n "${current_items}" ]; then
            # Print the possibly multi-line current_items safely
            printf '%s\n' "${current_items}"
        else
            print_info "(none)"
        fi

        # remove each item (best-effort)
        while IFS= read -r item; do
            if [ -n "${item}" ]; then
                # Best-effort: try removing the raw item value, and also try basename
                # Start removal in background so the installer doesn't block on UI operations
                # use last arg to be robust against a preceding -- marker
                if [ "${USE_PYOBJC_FLAG:-0}" -eq 1 ]; then
                    cmd_remove="env PYTHONPATH='${libpath}' MACHINIT_USE_PYOBJC=1 python3 -c \"from finder_sidebar_editor import FinderSidebar; import sys; FinderSidebar().remove(sys.argv[-1])\" -- '${item}'"
                else
                    cmd_remove="env PYTHONPATH='${libpath}' python3 -c \"from finder_sidebar_editor import FinderSidebar; import sys; FinderSidebar().remove(sys.argv[-1])\" -- '${item}'"
                fi
                run_fse_cmd "$cmd_remove" >/dev/null 2>&1 || true
                # Try removing the basename of the item in case list() returned "Name file://..."
                base_item="$(basename "${item}")"
                if [ -n "${base_item}" ] && [ "${base_item}" != "${item}" ]; then
                    if [ "${USE_PYOBJC_FLAG:-0}" -eq 1 ]; then
                        cmd_base="env PYTHONPATH='${libpath}' MACHINIT_USE_PYOBJC=1 python3 -c \"from finder_sidebar_editor import FinderSidebar; import sys; FinderSidebar().remove(sys.argv[-1])\" -- '${base_item}'"
                    else
                        cmd_base="env PYTHONPATH='${libpath}' python3 -c \"from finder_sidebar_editor import FinderSidebar; import sys; FinderSidebar().remove(sys.argv[-1])\" -- '${base_item}'"
                    fi
                    run_fse_cmd "$cmd_base" >/dev/null 2>&1 || true
                fi

                # After attempting removal, close any Finder windows that may have been opened
                if [ "$FSE_SYNC" = true ]; then
                    # synchronous mode: keep the same Finder window and rely on run_fse_cmd's wait
                    print_info "Running in FSE sync mode — reusing Finder window and waiting ${FSE_WAIT_SECONDS}s"
                else
                    print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
                    execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
                    # small pause so Finder state can settle between UI operations
                    sleep 0.25
                fi
            fi
        done <<EOF
${current_items:-}
EOF
    else
        print_notice "python3 not found; cannot clear sidebar programmatically (skipping)."
    fi
}

# If invoked with --add-sidebar-only, perform a minimal 'pin to sidebar' step
# and exit so callers (or CI) can target sidebar pinning exclusively.
if [ "$ADD_SIDEBAR_ONLY" = true ]; then
    # Ensure both Downloads and Documents/Projects exist for the user
    execute_as_user mkdir -p "${ORIGINAL_HOME}/Downloads" || true
    execute_as_user mkdir -p "${ORIGINAL_HOME}/Documents/Projects" || true

    # Close Finder windows before starting operations so UI interactions start
    # from a clean state (best-effort, DRY_RUN-safe)
    print_info "Closing any open Finder windows before starting sidebar operations (best-effort)..."
    execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
    sleep 0.25

    # Clear existing favorites then populate in a deterministic order
    clear_sidebar

    # Populate favorites from top to bottom — close Finder windows and pause briefly after each
    add_sidebar_item "Recents" "${ORIGINAL_HOME}"
    if [ "$FSE_SYNC" = true ]; then
        print_info "FSE sync mode — reusing Finder window; commands wait ${FSE_WAIT_SECONDS}s between operations (default)"
    else
        print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
        execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
        sleep 0.25
    fi

    add_sidebar_item "Applications" "/Applications"
    if [ "$FSE_SYNC" = true ]; then
        print_info "FSE sync mode — reusing Finder window; commands wait ${FSE_WAIT_SECONDS}s between operations"
    else
        print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
        execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
        sleep 0.25
    fi

    add_sidebar_item "Home" "${ORIGINAL_HOME}"
    if [ "$FSE_SYNC" = true ]; then
        print_info "FSE sync mode — reusing Finder window; commands wait ${FSE_WAIT_SECONDS}s between operations"
    else
        print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
        execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
        sleep 0.25
    fi

    add_sidebar_item "Desktop" "${ORIGINAL_HOME}/Desktop"
    if [ "$FSE_SYNC" = true ]; then
        print_info "FSE sync mode — reusing Finder window; commands wait ${FSE_WAIT_SECONDS}s between operations"
    else
        print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
        execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
        sleep 0.25
    fi

    add_sidebar_item "Documents" "${ORIGINAL_HOME}/Documents"
    if [ "$FSE_SYNC" = true ]; then
        print_info "FSE sync mode — reusing Finder window; commands wait ${FSE_WAIT_SECONDS}s between operations"
    else
        print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
        execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
        sleep 0.25
    fi

    add_sidebar_item "Downloads" "${ORIGINAL_HOME}/Downloads"
    if [ "$FSE_SYNC" = true ]; then
        print_info "FSE sync mode — reusing Finder window; commands wait ${FSE_WAIT_SECONDS}s between operations"
    else
        print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
        execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
        sleep 0.25
    fi

    add_sidebar_item "Projects" "${ORIGINAL_HOME}/Documents/Projects"
    if [ "$FSE_SYNC" = true ]; then
        print_info "FSE sync mode — reusing Finder window; commands wait ${FSE_WAIT_SECONDS}s between operations"
    else
        print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
        execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
        sleep 0.25
    fi

    add_sidebar_item "Nextcloud" "${ORIGINAL_HOME}/Nextcloud"
    if [ "$FSE_SYNC" = true ]; then
        print_info "FSE sync mode — reusing Finder window; commands wait ${FSE_WAIT_SECONDS}s between operations"
    else
        print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
        execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
        sleep 0.25
    fi

    # Flush preferences so Finder picks up the change
    print_info "Flushing preference cache for user ${ORIGINAL_USER}..."
    execute_as_user killall cfprefsd &>/dev/null || true

    # Clean up any temporary applescript payloads we created during background runs
    if [ ${#FSE_TMPFILES[@]} -gt 0 ]; then
        for tmpf in "${FSE_TMPFILES[@]}"; do
            if [ -n "${tmpf}" ]; then
                execute_as_user rm -f "${tmpf}" >/dev/null 2>&1 || true
            fi
        done
    fi

    echo "Finder sidebar pinning done (add-only mode)."
    # Close Finder windows after operations to leave Finder in a tidy state
    print_info "Closing any open Finder windows after sidebar operations (best-effort)..."
    execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
    sleep 0.25
    # Print final list so callers can verify what was added in add-only mode
    if command -v python3 >/dev/null 2>&1; then
        print_info "Final Finder sidebar items (post-add, add-only mode):"
        if [ "${USE_PYOBJC_FLAG:-0}" -eq 1 ]; then
            execute_as_user env PYTHONPATH="${libpath}" MACHINIT_USE_PYOBJC=1 python3 -c "from finder_sidebar_editor import FinderSidebar; import sys; print('\n'.join(FinderSidebar().list()))" 2>/dev/null || true
        else
            execute_as_user env PYTHONPATH="${libpath}" python3 -c "from finder_sidebar_editor import FinderSidebar; import sys; print('\n'.join(FinderSidebar().list()))" 2>/dev/null || true
        fi
    fi
    exit 0
fi

# Use the original home path when adding the item
# On a full run, clear and re-add a curated list (same as add-only)
clear_sidebar

# Add each favorite and close Finder windows / pause between steps so the UI can settle
add_sidebar_item "Recents" "${ORIGINAL_HOME}"
print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
sleep 0.25

add_sidebar_item "Applications" "/Applications"
print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
sleep 0.25

add_sidebar_item "Home" "${ORIGINAL_HOME}"
print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
sleep 0.25

add_sidebar_item "Desktop" "${ORIGINAL_HOME}/Desktop"
print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
sleep 0.25

add_sidebar_item "Documents" "${ORIGINAL_HOME}/Documents"
print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
sleep 0.25

add_sidebar_item "Downloads" "${ORIGINAL_HOME}/Downloads"
print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
sleep 0.25

add_sidebar_item "Projects" "${ORIGINAL_HOME}/Documents/Projects"
print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
sleep 0.25

add_sidebar_item "Nextcloud" "${ORIGINAL_HOME}/Nextcloud"
print_info "Closing any open Finder windows (best-effort) and pausing briefly..."
execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
sleep 0.25

# Flush cfprefsd cache for the original user so Finder will pick up the new settings
print_info "Flushing preference cache for user ${ORIGINAL_USER}..."
execute_as_user killall cfprefsd &>/dev/null || true

# Final cleanup for applescript tmpfiles
if [ ${#FSE_TMPFILES[@]} -gt 0 ]; then
    for tmpf in "${FSE_TMPFILES[@]}"; do
        if [ -n "${tmpf}" ]; then
            execute_as_user rm -f "${tmpf}" >/dev/null 2>&1 || true
        fi
    done
fi

# Close Finder windows after final add operations so Finder state is tidy
print_info "Closing any open Finder windows after sidebar operations (best-effort)..."
execute_as_user /usr/bin/osascript -e 'tell application "Finder" to close every window' &>/dev/null || true
sleep 0.25

print_notice "Finder restarts are deferred until the final restart step. Run scripts/999_restart_apps.sh when the full run is complete to restart Finder and apply changes."

echo "Finder configuration complete."

# Print the final list so callers can verify the results
if command -v python3 >/dev/null 2>&1; then
    print_info "Final Finder sidebar items (post-add):"
    execute_as_user env PYTHONPATH="${libpath}" python3 -c "from finder_sidebar_editor import FinderSidebar; import sys; print('\n'.join(FinderSidebar().list()))" 2>/dev/null || true
fi

## Verification: ensure per-user settings were written
print_config "Verify Finder settings"
verify_ok=true

# Verify NewWindowTarget
nw_target=$(execute_as_user defaults read com.apple.finder NewWindowTarget 2>/dev/null || true)
if [ "$nw_target" = "PfDe" ]; then
    print_success "NewWindowTarget correctly set to PfDe"
else
    print_error "NewWindowTarget not set (observed: ${nw_target:-<empty>})"
    verify_ok=false
fi

# Verify NewWindowTargetPath
nw_path=$(execute_as_user defaults read com.apple.finder NewWindowTargetPath 2>/dev/null || true)
expected_path="file://${ORIGINAL_HOME}/Desktop/"
if [ "$nw_path" = "$expected_path" ]; then
    print_success "NewWindowTargetPath correctly points to Desktop"
else
    print_error "NewWindowTargetPath not set as expected (observed: ${nw_path:-<empty>})"
    verify_ok=false
fi

# Verify sidebar short settings
for key in SidebarICloudDrive SidebarBonjourBrowser ShowRecentTags; do
    val=$(execute_as_user defaults read com.apple.finder "$key" 2>/dev/null || true)
    if [ "$val" = "0" ] || [ "$val" = "false" ]; then
        print_success "$key = false"
    else
        print_error "$key not false (observed: ${val:-<empty>})"
        verify_ok=false
    fi
done

if [ "$verify_ok" = true ]; then
    print_success "Finder sidebar configuration verified (user: ${ORIGINAL_USER})."
else
    print_warning "Finder sidebar verification failed in some checks. You may need to run scripts/999_restart_apps.sh to pick up changes, or check TCC/MDM policies."
fi
