#!/usr/bin/env python3
"""finder_sidebar_editor — tiny helper for Finder sidebar operations.

Provides a lightweight, dependency-light API for adding, removing, listing
and moving items in the Finder Favorites (sidebar). Designed to be used by
the installer scripts in this repo under scripts/lib.

The implementation is intentionally best-effort and safe for DRY_RUN testing.
It prefers to use mysides when that binary is available _and_ the caller wants
that path; otherwise it uses AppleScript UI automation for best-effort changes.

Usage:
    from finder_sidebar_editor import FinderSidebar
    fs = FinderSidebar()
    fs.add('/Users/alice/Documents/Projects')
    fs.list()
    fs.remove('Projects')
    fs.move('Projects', 1)
"""

from __future__ import annotations

import os
import subprocess
import sys
import urllib.parse
import plistlib
from typing import List, Optional


class FinderSidebar:
    """API for Finder sidebar operations.

    Methods are best-effort. They raise RuntimeError on unrecoverable errors.
    When DRY_RUN is enabled in the environment this class will print actions but
    not attempt to modify the system.
    """

    def __init__(
        self,
        allow_mysides: Optional[bool] = None,
        allow_pyobjc: Optional[bool] = None,
        allow_verbose: Optional[bool] = None,
    ):
        # Respect DRY_RUN via environment like before
        self._dry_run = os.environ.get("DRY_RUN") not in (
            None,
            "0",
            "false",
            "False",
            "FALSE",
        )

        # Allow callers to explicitly enable mysides on a per-instance basis
        # via the allow_mysides parameter. If not provided, fall back to the
        # MACHINIT_USE_MYSIDES environment variable (unchanged behaviour).
        if allow_mysides is None:
            self._allow_mysides = os.environ.get("MACHINIT_USE_MYSIDES") not in (
                None,
                "0",
                "false",
                "False",
                "FALSE",
            )
        else:
            self._allow_mysides = bool(allow_mysides)
        # Optional pyobjc / LSSharedFileList path (opt-in only).
        if allow_pyobjc is None:
            self._allow_pyobjc = os.environ.get("MACHINIT_USE_PYOBJC") not in (
                None,
                "0",
                "false",
                "False",
                "FALSE",
            )
        else:
            self._allow_pyobjc = bool(allow_pyobjc)
        # Optional verbose logging for debugging; opt-in via constructor or
        # MACHINIT_FSE_VERBOSE env var (non-zero/non-false enables verbose output)
        if allow_verbose is None:
            self._verbose = os.environ.get("MACHINIT_FSE_VERBOSE") not in (
                None,
                "0",
                "false",
                "False",
                "FALSE",
            )
        else:
            self._verbose = bool(allow_verbose)

    def _run(
        self, cmd: List[str], timeout: Optional[float] = None, **kwargs
    ) -> subprocess.CompletedProcess:
        try:
            # debug logging (best-effort)
            try:
                self._debug("_run:", cmd, "timeout:", timeout)
            except Exception:
                pass
            # Use a modest default timeout for UI automation or external CLI
            if timeout is None:
                timeout = 10.0
            return subprocess.run(
                cmd,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
                **kwargs,
            )
        except FileNotFoundError:
            # emulate a non-zero returncode to indicate missing binary
            cp = subprocess.CompletedProcess(cmd, returncode=127)
            return cp

    def _debug(self, *parts: object) -> None:
        """Print debugging information when verbose mode is enabled.

        We write debug output to stderr to keep normal stdout stable for tests
        and CLI consumers.
        """
        if not self._verbose:
            return
        try:
            import sys

            print("[FSE DEBUG]", *parts, file=sys.stderr)
        except Exception:
            # best-effort logging only
            pass

    def _retry_cmd(
        self,
        cmd: List[str],
        retries: int = 2,
        delay: float = 0.15,
        timeout: Optional[float] = None,
        **kwargs,
    ) -> subprocess.CompletedProcess:
        """Run a command with a small retry/backoff loop for transient failures.

        The function invokes _run and will sleep for an increasing amount of
        time between attempts. It returns the last CompletedProcess.
        """
        attempt = 0
        last = None
        while attempt <= retries:
            try:
                self._debug(
                    "_retry_cmd attempt",
                    attempt + 1,
                    "of",
                    retries + 1,
                    "->",
                    cmd,
                )
            except Exception:
                pass
            last = self._run(cmd, timeout=timeout, **kwargs)
            if last.returncode == 0:
                try:
                    self._debug("_retry_cmd success:", cmd)
                except Exception:
                    pass
                return last
            attempt += 1
            # small backoff
            try:
                import time

                time.sleep(delay * attempt)
            except Exception:
                pass
        return last

    def _pyobjc_available(self) -> bool:
        """Return True if pyobjc-based LaunchServices APIs are importable.

        Only returns True when the instance is configured to allow pyobjc
        (opt-in), and the expected modules can be imported.
        """
        if not self._allow_pyobjc:
            return False
        try:
            import LaunchServices  # type: ignore # noqa: F401
            import Foundation  # type: ignore # noqa: F401

            return True
        except Exception:
            return False

    def _file_url(self, path: str) -> str:
        p = os.path.expanduser(path)
        p = os.path.abspath(p)
        return "file://" + urllib.parse.quote(p, safe="/")

    def add(self, path: str, name: Optional[str] = None) -> bool:
        """Add a filesystem path to the Finder favorites/sidebar.

        Returns True on success. In DRY_RUN mode the call is logged and returns True.
        """
        if sys.platform != "darwin":
            raise RuntimeError("FinderSidebar is only supported on macOS (darwin)")

        if not path:
            raise ValueError("path is required")

        target = os.path.expanduser(path)
        target = os.path.abspath(target)

        if self._dry_run:
            print(f"[DRY_RUN] add: {target}")
            return True

        if not os.path.exists(target):
            raise RuntimeError(f"target does not exist: {target}")

        # Try mysides if available
        # Allow tests and callers to override the mysides path via MACHINIT_MYSIDES
        # Only attempt mysides if explicitly allowed by environment
        if not self._allow_mysides:
            mysides_candidates = []
        else:
            env_override = os.environ.get("MACHINIT_MYSIDES")
            mysides_candidates = []
            if env_override:
                mysides_candidates.append(env_override)
        mysides_candidates.extend(
            ("/usr/local/bin/mysides", "/opt/homebrew/bin/mysides", "/usr/bin/mysides")
        )

        for mysides in mysides_candidates:
            if os.path.exists(mysides) and os.access(mysides, os.X_OK):
                friendly = name or os.path.basename(target) or target
                # try the file:// URL form first
                fileurl = self._file_url(target)
                cp = self._retry_cmd([mysides, "add", friendly, fileurl])
                if cp.returncode == 0:
                    return True
                cp = self._retry_cmd([mysides, "add", friendly, target])
                if cp.returncode == 0:
                    return True

        # If allowed, try the native macOS LSSharedFileList API via pyobjc.
        if self._pyobjc_available():
            try:
                from Foundation import NSURL  # type: ignore
                from LaunchServices import (
                    LSSharedFileListCreate,  # type: ignore
                    kLSSharedFileListFavorites,  # type: ignore
                    LSSharedFileListInsertItemURL,  # type: ignore
                )

                shared = LSSharedFileListCreate(None, kLSSharedFileListFavorites, None)
                url = NSURL.fileURLWithPath_(target)
                # Insert at end (None for position)
                LSSharedFileListInsertItemURL(shared, None, None, None, url, None, None)
                return True
            except Exception:
                # best-effort: fall back to AppleScript
                pass

        # AppleScript fallback (UI automation) — best-effort
        applescript = """
tell application "Finder"
    try
        set targetFolder to (POSIX file "{target}") as alias
        open targetFolder
        delay 0.2
        set selection to targetFolder
    end try
end tell
tell application "System Events"
    tell process "Finder"
        try
            click menu item "Add to Sidebar" of menu "File" of menu bar 1
        on error
            -- ignore UI errors
        end try
    end tell
end tell
"""

        cp = self._retry_cmd(
            ["/usr/bin/osascript", "-e", applescript], retries=3, delay=0.2
        )
        return cp.returncode == 0

    def list(self) -> List[str]:
        """Return a best-effort list of favorites sidebar entries (names or paths).

        The output may vary by system; this method returns a list of strings.
        """
        if self._dry_run:
            print("[DRY_RUN] list")
            return []

        # Try mysides if present for a clean listing (only when explicitly enabled)
        if not self._allow_mysides:
            mysides_candidates = []
        else:
            env_override = os.environ.get("MACHINIT_MYSIDES")
            mysides_candidates = []
            if env_override:
                mysides_candidates.append(env_override)
        mysides_candidates.extend(
            ("/usr/local/bin/mysides", "/opt/homebrew/bin/mysides", "/usr/bin/mysides")
        )

        for mysides in mysides_candidates:
            if os.path.exists(mysides) and os.access(mysides, os.X_OK):
                cp = self._retry_cmd([mysides, "list"], retries=2, delay=0.12)
                if cp.returncode == 0:
                    out = cp.stdout.decode().strip().splitlines()
                    # Parse lines like "Name <separator> URL" — extract the friendly name
                    parsed = []
                    for ln in out:
                        ln = ln.strip()
                        if not ln:
                            continue
                        # Normalize mysides output that may use 'name|path' or embed a file://
                        if "|" in ln:
                            left, rest = ln.split("|", 1)
                            left = left.strip()
                            rest = rest.strip()
                            if rest.startswith("file://"):
                                path = urllib.parse.unquote(rest)
                            else:
                                path = rest
                            name = left or os.path.basename(path)
                            parsed.append(f"{name}|{path}")
                            continue
                        # If the line contains a file:// URL without an explicit '|',
                        # the friendly name is usually before it
                        idx = ln.rfind("file://")
                        if idx != -1:
                            name = ln[:idx].strip().rstrip("|")
                            fileurl = ln[idx:].strip()
                            path = urllib.parse.unquote(fileurl)
                            if not name:
                                name = os.path.basename(path)
                            parsed.append(f"{name}|{path}")
                            continue
                        # Otherwise use the whole line
                        parsed.append(ln)
                    return parsed

            # If allowed, try the native macOS LSSharedFileList API via pyobjc.
            if self._pyobjc_available():
                try:
                    from LaunchServices import (
                        LSSharedFileListCreate,  # type: ignore
                        kLSSharedFileListFavorites,  # type: ignore
                        LSSharedFileListCopySnapshot,  # type: ignore
                        LSSharedFileListItemCopyResolvedURL,  # type: ignore
                    )

                    shared = LSSharedFileListCreate(
                        None, kLSSharedFileListFavorites, None
                    )
                    items, seed = LSSharedFileListCopySnapshot(shared, None)
                    parsed = []
                    for it in items:
                        try:
                            url, flags = LSSharedFileListItemCopyResolvedURL(
                                it, 0, None
                            )
                            if url is not None:
                                p = url.path()
                                parsed.append(f"{os.path.basename(p) or p}|{p}")
                        except Exception:
                            # ignore problematic items
                            pass
                    if parsed:
                        return parsed
                except Exception:
                    # fallback to plist/defaults parsing
                    pass

            # Fallback: read Finder sidebar prefs (best-effort parsing)
        # Next try reading the user's preferences plist directly (best-effort)
        try:
            prefs_path = os.path.expanduser(
                "~/Library/Preferences/com.apple.sidebarlists.plist"
            )
            if os.path.exists(prefs_path):
                with open(prefs_path, "rb") as f:
                    obj = plistlib.load(f)

                # Recursively search the plist for 'Name' or URL-like entries
                def _collect_names(o):
                    names = []
                    if isinstance(o, dict):
                        for k, v in o.items():
                            if (
                                isinstance(k, str)
                                and k.lower() == "name"
                                and isinstance(v, str)
                            ):
                                names.append(v)
                            else:
                                names.extend(_collect_names(v))
                    elif isinstance(o, (list, tuple)):
                        for item in o:
                            names.extend(_collect_names(item))
                    elif isinstance(o, str):
                        # if the string looks like a path/url, use its basename
                        if "file://" in o or o.startswith("/"):
                            names.append(os.path.basename(urllib.parse.unquote(o)))
                    return names

                parsed = _collect_names(obj)
                if parsed:
                    # preserve order and uniqueness
                    seen = set()
                    out = []
                    for n in parsed:
                        if n and n not in seen:
                            seen.add(n)
                            out.append(n)
                    return out
        except Exception:
            # best-effort — fall back to defaults read if available
            pass

        cp = self._retry_cmd(
            ["/usr/bin/defaults", "read", "com.apple.sidebarlists"],
            retries=2,
            delay=0.12,
            stderr=subprocess.DEVNULL,
        )
        if cp.returncode == 0 and cp.stdout:
            # Attempt simple parsing: find file:// occurrences and use the preceding tokens as names
            txt = cp.stdout.decode()
            lines = txt.splitlines()
            parsed = []
            for ln in lines:
                ln = ln.strip()
                if not ln:
                    continue
                idx = ln.rfind("file://")
                if idx != -1:
                    name = ln[:idx].strip()
                    if not name:
                        name = os.path.basename(urllib.parse.unquote(ln[idx:]))
                    parsed.append(name)
                elif len(ln) < 256:
                    parsed.append(ln)
            if parsed:
                return parsed

        raise RuntimeError(
            "Unable to list Finder sidebar items (no mysides and failed to read prefs)"
        )

    def remove(self, name: str) -> bool:
        """Attempt to remove a sidebar item by name.

        Returns True on success. May raise RuntimeError on unrecoverable failure.
        """
        if self._dry_run:
            print(f"[DRY_RUN] remove: {name}")
            return True

        # Guardrails: avoid accidental destructive calls
        if not name or not isinstance(name, str) or not name.strip():
            raise ValueError("name is required")
        if name.strip() in ("/", "."):
            raise ValueError("refusing to remove root or ambiguous name")

        # If the name looks like a file:// URL, try to derive path
        target_path = None
        if name and name.startswith("file://"):
            target_path = urllib.parse.unquote(name[len("file://") :])

        # Try mysides remove/rm first (only when explicitly allowed)
        if not self._allow_mysides:
            mysides_candidates = []
        else:
            env_override = os.environ.get("MACHINIT_MYSIDES")
            mysides_candidates = []
            if env_override:
                mysides_candidates.append(env_override)
            mysides_candidates.extend(
                (
                    "/usr/local/bin/mysides",
                    "/opt/homebrew/bin/mysides",
                    "/usr/bin/mysides",
                )
            )
        for mysides in mysides_candidates:
            if os.path.exists(mysides) and os.access(mysides, os.X_OK):
                # try both 'remove' and 'rm'
                for cmd in ("remove", "rm"):
                    # Try the name first
                    self._debug("mysides", cmd, "->", name)
                    cp = self._retry_cmd([mysides, cmd, name], retries=2, delay=0.12)
                    if cp.returncode == 0:
                        # re-list to confirm the removal actually happened
                        try:
                            after = self.list()
                        except Exception:
                            after = []
                        still_present = any(
                            (name.lower() in str(c).lower()) for c in after if c
                        )
                        if not still_present:
                            self._debug("mysides", cmd, name, "removed (verified)")
                            return True
                        self._debug(
                            "mysides",
                            cmd,
                            name,
                            "reported success but target still present",
                        )

                    # Try file:// URL form
                    if target_path is None and os.path.exists(name):
                        # caller passed a path — try file:// form
                        fileurl = self._file_url(name)
                        cp = self._retry_cmd(
                            [mysides, cmd, fileurl], retries=2, delay=0.12
                        )
                        if cp.returncode == 0:
                            return True

                    if target_path is not None:
                        # if we resolved a path from a file://, try removing that path too
                        cp = self._retry_cmd(
                            [mysides, cmd, target_path], retries=2, delay=0.12
                        )
                        if cp.returncode == 0:
                            try:
                                after = self.list()
                            except Exception:
                                after = []
                            still_present = any(
                                (target_path in str(c))
                                or (name.lower() in str(c).lower())
                                for c in after
                                if c
                            )
                            if not still_present:
                                self._debug(
                                    "mysides", cmd, target_path, "removed (verified)"
                                )
                                return True
                            self._debug(
                                "mysides",
                                cmd,
                                target_path,
                                "reported success but target still present",
                            )

                    # As a final attempt try the basename of the provided name
                    base = os.path.basename(name)
                    if base and base != name:
                        cp = self._retry_cmd(
                            [mysides, cmd, base], retries=2, delay=0.12
                        )
                        if cp.returncode == 0:
                            return True

                    # Also try to find a candidate from the listing and remove that
                    try:
                        candidates = self.list()
                    except Exception:
                        candidates = []
                    for cand in candidates:
                        if cand and name.lower() in cand.lower():
                            # If candidate includes a 'name|path' form, prefer the friendly
                            # name portion when calling mysides (external tool expects name)
                            candidate_arg = (
                                cand.split("|", 1)[0] if "|" in cand else cand
                            )
                            cp = self._retry_cmd(
                                [mysides, cmd, candidate_arg], retries=2, delay=0.12
                            )
                            if cp.returncode == 0:
                                # verify it's gone
                                try:
                                    after = self.list()
                                except Exception:
                                    after = []
                                still_present = any(
                                    (name.lower() in str(c).lower()) for c in after if c
                                )
                                if not still_present:
                                    return True
                                self._debug(
                                    "mysides",
                                    cmd,
                                    candidate_arg,
                                    "reported success but target still present",
                                )

        # If available, try to remove using the native LSSharedFileList APIs via pyobjc
        if self._pyobjc_available():
            try:
                from LaunchServices import (
                    LSSharedFileListCreate,  # type: ignore
                    kLSSharedFileListFavorites,  # type: ignore
                    LSSharedFileListCopySnapshot,  # type: ignore
                    LSSharedFileListItemCopyResolvedURL,  # type: ignore
                    LSSharedFileListItemRemove,  # type: ignore
                )

                shared = LSSharedFileListCreate(None, kLSSharedFileListFavorites, None)
                items, seed = LSSharedFileListCopySnapshot(shared, None)
                for it in items:
                    try:
                        url, flags = LSSharedFileListItemCopyResolvedURL(it, 0, None)
                        p = None
                        if url is not None:
                            p = url.path()
                        # Build comparison candidates
                        candidates = [name]
                        if p:
                            candidates.append(p)
                            candidates.append(os.path.basename(p))
                        for cand in candidates:
                            if (
                                cand
                                and isinstance(cand, str)
                                and cand.lower() in (name or "").lower()
                            ):
                                try:
                                    LSSharedFileListItemRemove(shared, it)
                                    # verify removal via our list() (best-effort)
                                    try:
                                        after = self.list()
                                    except Exception:
                                        after = []
                                    found = any(
                                        (cand.lower() in str(c).lower())
                                        for c in after
                                        if c
                                    )
                                    if not found:
                                        self._debug("pyobjc removed item", cand)
                                        return True
                                    self._debug(
                                        "pyobjc reported removal but item still present (verified)",
                                        cand,
                                    )
                                except Exception:
                                    # If removing this specific item fails, continue to try others
                                    pass
                    except Exception:
                        pass
            except Exception:
                # fall back to AppleScript if pyobjc removal fails
                pass

        # Best-effort AppleScript: find item in sidebar and remove via UI
        # Best-effort AppleScript: try selecting the item via UI and use the "Remove from Sidebar" menu.
        # UI scripting is fragile and localized; we attempt a few approaches.
        safe_name = name.replace('"', '\\"') if isinstance(name, str) else name
        applescript = f"""
try
    tell application "Finder"
        activate
    end tell
    delay 0.1
    tell application "System Events"
        tell process "Finder"
            -- Try to click a sidebar element matching the name
            try
                repeat with anOutline in (every outline of scroll area 1 of splitter group 1 of window 1)
                    try
                        repeat with r in (UI elements of anOutline)
                            try
                                if (value of attribute "AXTitle" of r as string) contains "{safe_name}" then
                                    perform action "AXPress" of r
                                    delay 0.1
                                    -- invoke the File menu remove action
                                    try
                                        click menu item "Remove from Sidebar" of menu "File" of menu bar 1
                                    end try
                                    return
                                end if
                            end try
                        end repeat
                    end try
                end repeat
            end try
        end tell
    end tell
on error
    -- best-effort; ignore UI failures
end try
"""
        cp = self._retry_cmd(
            ["/usr/bin/osascript", "-e", applescript], retries=3, delay=0.2
        )
        if cp.returncode != 0:
            return False
        # verify the item actually disappeared
        try:
            after = self.list()
        except Exception:
            after = []
        still_present = any((name.lower() in str(c).lower()) for c in after if c)
        if not still_present:
            self._debug("osascript removed (verified)", name)
            return True
        self._debug("osascript reported success but item still present", name)
        return False

    def remove_all(self) -> bool:
        """Remove all sidebar favorites (best-effort).

        This performs a best-effort iteration over the current list() of
        entries and attempts to remove each one. If any remove operation
        returns non-zero (failure) the method still proceeds; it returns
        True if all removals either succeed or are treated as OK.
        """
        if self._dry_run:
            print("[DRY_RUN] remove_all")
            return True

        try:
            items = self.list()
        except Exception:
            items = []

        ok = True
        for item in items:
            # Some backends (like a fake mysides in tests) may return 'Name|path'
            # Prefer removal by the path when available as it is more precise
            # (e.g. when multiple items share the same friendly name).
            if isinstance(item, str) and "|" in item:
                name_part, path_part = item.split("|", 1)
                # Prefer removing by friendly name first (works for mysides
                # and many backends). If that fails, fall back to path-based
                # removal which is more deterministic for native backends.
                if name_part and self.remove(name_part):
                    res = True
                elif path_part and self.remove_by_path(path_part):
                    res = True
                else:
                    res = False
            else:
                res = self.remove(item)
            ok = ok and bool(res)

        return ok

    def remove_by_path(self, path: str) -> bool:
        """Attempt to remove a sidebar entry identified by a filesystem path.

        The method will try a file:// variant and basename and fall back to
        the normal remove behaviour if necessary.
        """
        if self._dry_run:
            print(f"[DRY_RUN] remove_by_path: {path}")
            return True

        if not path:
            raise ValueError("path is required")

        # Normalize path. Support incoming file:// URLs by unwrapping them.
        if path.startswith("file://"):
            try:
                path = urllib.parse.unquote(path[len("file://") :])
            except Exception:
                pass
        target = os.path.abspath(os.path.expanduser(path))

        # Normalize base early — used for matching and verification below
        base = os.path.basename(target)

        # Try mysides if allowed
        if self._allow_mysides:
            env_override = os.environ.get("MACHINIT_MYSIDES")
            mysides_candidates = []
            if env_override:
                mysides_candidates.append(env_override)
            mysides_candidates.extend(
                (
                    "/usr/local/bin/mysides",
                    "/opt/homebrew/bin/mysides",
                    "/usr/bin/mysides",
                )
            )

            for mysides in mysides_candidates:
                if os.path.exists(mysides) and os.access(mysides, os.X_OK):
                    fileurl = self._file_url(target)
                    cp = self._retry_cmd(
                        [mysides, "rm", fileurl], retries=2, delay=0.12
                    )
                    if cp.returncode == 0:
                        # mysides may return 0 even when nothing was removed (fake mysides
                        # used in tests behaves this way). Verify the item is gone by
                        # re-listing and checking for the target/base; only treat as
                        # success if the candidate is absent.
                        try:
                            after = self.list()
                        except Exception:
                            after = []
                        still_present = any(
                            (target in str(c)) or (base and base in str(c))
                            for c in after
                        )
                        if not still_present:
                            return True
                    cp = self._retry_cmd([mysides, "rm", target], retries=2, delay=0.12)
                    if cp.returncode == 0:
                        try:
                            after = self.list()
                        except Exception:
                            after = []
                        still_present = any(
                            (target in str(c)) or (base and base in str(c))
                            for c in after
                        )
                        if not still_present:
                            return True

        # As an alternative try to remove items that include the basename/path
        try:
            candidates = self.list()
        except Exception:
            candidates = []

        for cand in candidates:
            # match on path content or basename
            if cand and (base and base in cand or target in cand):
                # If backend returns 'name|path' prefer to remove by friendly name
                if isinstance(cand, str) and "|" in cand:
                    cand_name = cand.split("|", 1)[0]
                else:
                    cand_name = cand
                if self.remove(cand_name):
                    # Ensure the item actually disappeared from the listing — some
                    # backends may report success while making no real change.
                    try:
                        after = self.list()
                    except Exception:
                        after = []
                    still_present = any(
                        (target in str(c)) or (base and base in str(c)) for c in after
                    )
                    if not still_present:
                        return True

        # Best-effort fallback: call remove() directly with the target
        return self.remove(target)

    def get_index_from_name(self, name: str) -> Optional[int]:
        """Return 1-based index of the sidebar item matching name, or None."""
        if self._dry_run:
            print(f"[DRY_RUN] get_index_from_name: {name}")
            return None

        try:
            items = self.list()
        except Exception:
            return None

        for idx, val in enumerate(items, start=1):
            if not val:
                continue
            # Support name|path format returned by list() — compare both friendly name and path
            if "|" in val:
                try:
                    name_part, path_part = val.split("|", 1)
                except Exception:
                    name_part = val
                    path_part = ""
                if name_part and name_part.lower() == name.lower():
                    return idx
                if path_part and name.lower() in path_part.lower():
                    return idx
            else:
                if val.lower() == name.lower():
                    return idx
                return idx

        return None

    def get_name_from_index(self, index: int) -> Optional[str]:
        """Return the name at 1-based index (or None if not found)."""
        if self._dry_run:
            print(f"[DRY_RUN] get_name_from_index: {index}")
            return None

        try:
            items = self.list()
        except Exception:
            return None

        if index <= 0 or index > len(items):
            return None

        val = items[index - 1]
        if isinstance(val, str) and "|" in val:
            return val.split("|", 1)[0]
        return val

    def synchronize(self) -> bool:
        """Best-effort synchronization so Finder picks up changes (flush prefs).

        This is a best-effort convenience wrapper and may not be required in
        all environments.
        """
        if self._dry_run:
            print("[DRY_RUN] synchronize")
            return True

        # Best-effort preference read to nudge macOS into realizing any changes;
        # we avoid destructive commands here so the function remains safe.
        cp = self._retry_cmd(
            ["/usr/bin/defaults", "read", "com.apple.sidebarlists"],
            retries=2,
            delay=0.12,
        )
        return cp.returncode == 0

    def move(self, name: str, position: int) -> bool:
        """Move a sidebar item to a new (1-based) position – best-effort.

        This method tries to use mysides if available, otherwise it's a noop
        or attempts a UI automation. Returns True on success.
        """
        if self._dry_run:
            print(f"[DRY_RUN] move: {name} -> {position}")
            return True

        # Try mysides move if it supports it (best-effort) and only when allowed
        if not self._allow_mysides:
            mysides_candidates = []
        else:
            env_override = os.environ.get("MACHINIT_MYSIDES")
            mysides_candidates = []
            if env_override:
                mysides_candidates.append(env_override)
            mysides_candidates.extend(
                (
                    "/usr/local/bin/mysides",
                    "/opt/homebrew/bin/mysides",
                    "/usr/bin/mysides",
                )
            )
        for mysides in mysides_candidates:
            if os.path.exists(mysides) and os.access(mysides, os.X_OK):
                cp = self._retry_cmd(
                    [mysides, "move", name, str(position)], retries=2, delay=0.12
                )
                if cp.returncode == 0:
                    return True

        # If allowed, attempt a native pyobjc reorder (best-effort)
        if self._pyobjc_available():
            try:
                from LaunchServices import (
                    LSSharedFileListCreate,  # type: ignore
                    kLSSharedFileListFavorites,  # type: ignore
                    LSSharedFileListCopySnapshot,  # type: ignore
                    LSSharedFileListItemCopyResolvedURL,  # type: ignore
                    LSSharedFileListItemRemove,  # type: ignore
                    LSSharedFileListInsertItemURL,  # type: ignore
                )

                shared = LSSharedFileListCreate(None, kLSSharedFileListFavorites, None)
                items, seed = LSSharedFileListCopySnapshot(shared, None)
                # locate the item to move
                found_item = None
                found_url = None
                for it in items:
                    try:
                        url, flags = LSSharedFileListItemCopyResolvedURL(it, 0, None)
                        if url is not None:
                            p = url.path()
                            if (
                                name.lower() == os.path.basename(p).lower()
                                or name.lower() in os.path.basename(p).lower()
                            ):
                                found_item = it
                                found_url = url
                                break
                    except Exception:
                        continue

                if found_item is not None and found_url is not None:
                    try:
                        # remove existing
                        LSSharedFileListItemRemove(shared, found_item)
                    except Exception:
                        pass

                    # compute insertion point (after_item) — position is 1-based
                    after_item = None
                    if position > 1 and position - 2 < len(items):
                        after_item = items[position - 2]

                    try:
                        LSSharedFileListInsertItemURL(
                            shared, after_item, None, None, found_url, None, None
                        )
                        return True
                    except Exception:
                        pass
            except Exception:
                # fallback to other methods below
                pass

        # UI automation fallback is complex; attempt best-effort AppleScript
        applescript = """
-- UI move is a no-op fallback here; reordering via AppleScript is non-trivial
return 1
"""
        # Attempt a no-op that returns non-success
        cp = self._retry_cmd(
            ["/usr/bin/osascript", "-e", applescript], retries=2, delay=0.12
        )
        return cp.returncode == 0


def main(argv=None) -> int:
    argv = list(argv or sys.argv[1:])

    import argparse

    parser = argparse.ArgumentParser(prog="finder_sidebar_editor")
    # Global option: only allow mysides when explicitly requested by CLI flag
    # If the flag is omitted, use_mysides will be None so the FinderSidebar
    # instance falls back to the MACHINIT_USE_MYSIDES environment variable.
    parser.add_argument(
        "--use-mysides",
        action="store_true",
        dest="use_mysides",
        default=None,
        help="Allow use of external mysides binary (explicit opt-in)",
    )
    parser.add_argument(
        "--use-pyobjc",
        action="store_true",
        dest="use_pyobjc",
        default=None,
        help="Allow use of native pyobjc LSSharedFileList APIs (explicit opt-in)",
    )
    sub = parser.add_subparsers(dest="cmd")

    p_add = sub.add_parser("add")
    p_add.add_argument("path")
    p_add.add_argument("--name", default=None)

    p_rm = sub.add_parser("remove")
    p_rm.add_argument("name")

    sub.add_parser("list")

    p_move = sub.add_parser("move")
    p_move.add_argument("name")
    p_move.add_argument("position", type=int)

    # Additional commands to mirror the original script's surface
    sub.add_parser("remove-all")

    p_rbp = sub.add_parser("remove-by-path")
    p_rbp.add_argument("path")

    p_idx = sub.add_parser("get-index")
    p_idx.add_argument("name")

    p_name = sub.add_parser("get-name")
    p_name.add_argument("index", type=int)

    sub.add_parser("sync")

    args = parser.parse_args(argv)
    # honor the global --use-mysides and --use-pyobjc flags (these do not change environment)
    fs = FinderSidebar(
        allow_mysides=getattr(args, "use_mysides", None),
        allow_pyobjc=getattr(args, "use_pyobjc", None),
    )

    try:
        if args.cmd == "add":
            ok = fs.add(args.path, name=args.name)
            print("Added" if ok else "Failed")
            return 0 if ok else 2

        if args.cmd == "remove":
            ok = fs.remove(args.name)
            print("Removed" if ok else "Failed")
            return 0 if ok else 2

        if args.cmd == "list":
            items = fs.list()
            for line in items:
                print(line)
            return 0

        if args.cmd == "remove-all":
            ok = fs.remove_all()
            print("RemovedAll" if ok else "Failed")
            return 0 if ok else 2

        if args.cmd == "remove-by-path":
            ok = fs.remove_by_path(args.path)
            print("Removed" if ok else "Failed")
            return 0 if ok else 2

        if args.cmd == "get-index":
            idx = fs.get_index_from_name(args.name)
            if idx is None:
                return 2
            print(idx)
            return 0

        if args.cmd == "get-name":
            nm = fs.get_name_from_index(args.index)
            if nm is None:
                return 2
            print(nm)
            return 0

        if args.cmd == "sync":
            ok = fs.synchronize()
            print("Synced" if ok else "Failed")
            return 0 if ok else 2

        if args.cmd == "move":
            ok = fs.move(args.name, args.position)
            print("Moved" if ok else "Failed")
            return 0 if ok else 2

    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 3

    parser.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
