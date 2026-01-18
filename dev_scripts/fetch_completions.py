#!/usr/bin/env python3
"""Fetch zsh completion files from common upstream sources.

Tries these locations (in order) for each completion name:
 - zsh-users/zsh-completions (src/_name)
 - ohmyzsh plugins (plugins/name/_name)

Saves downloads to assets/completions/_name if found and not already present.

Usage: ./dev_scripts/fetch_completions.py [name [name ...]]
If no names are supplied, it tries a built-in list.
"""

import sys
import subprocess
import shutil
import os
import urllib.request

ROOT = os.path.dirname(os.path.dirname(__file__))
OUT_DIR = os.path.join(ROOT, "assets", "completions")

DEFAULTS = [
    "npm",
    "npx",
    "yarn",
    "curl",
    "rg",
    "ripgrep",
    "node",
    "black",
    "chown",
    "chmod",
    "copilot",
    "clang",
    "clang++",
    "cargo",
    "cmake",
    "code",
    "cp",
    "cron",
    "crontab",
    "dd",
    "df",
    "dig",
    "dockutil",
    "du",
    "egrep",
    "find",
    "fgrep",
    "fmt",
    "flake8",
    "git",
    "gh",
    "github",
    "g++",
    "gcc",
    "grep",
    "gnumake",
    "hexdump",
    "ip",
    "ipconfig",
    "ld",
    "ln",
    "mount",
    "mkdir",
    "cat",
    "nvm",
    "nvram",
    "ping",
    "nslookup",
    "ps",
    "rsync",
    "rustc",
    "shellcheck",
    "ssh",
    "sort",
    "tar",
    "vcpkg",
    "xargs",
    "wget",
    "which",
]

# Alternate lookup names for commands that differ between projects or have
# characters that can break URL path lookups (e.g. g++). The fetcher will try
# these alternatives when looking for upstream files.
ALTERNATES = {
    "rg": ["rg", "ripgrep"],
    "ripgrep": ["rg", "ripgrep"],
    "g++": ["g++", "gcc"],
    "clang++": ["clang++", "clang"],
    "npx": ["npx", "npm"],
    "github": ["gh"],
}

SOURCES = [
    # zsh-style files
    "https://raw.githubusercontent.com/zsh-users/zsh-completions/master/src/_{name}",
    "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/{name}/_{name}",
    # bash-completion variants (many projects put completions here)
    (
        "https://raw.githubusercontent.com/scop/bash-completion/"
        "master/completions/{name}"
    ),
    (
        "https://raw.githubusercontent.com/bash-completion/"
        "bash-completion/master/completions/{name}"
    ),
    # some projects keep completion in top-level completion/ dir or completions/
    "https://raw.githubusercontent.com/{owner}/{repo}/master/completions/{name}",
    "https://raw.githubusercontent.com/{owner}/{repo}/master/completion/{name}",
    "https://raw.githubusercontent.com/{owner}/{repo}/master/completions/_{name}",
    "https://raw.githubusercontent.com/{owner}/{repo}/master/_{name}",
    # git contrib or project-level completions
    "https://raw.githubusercontent.com/git/git/master/contrib/completion/{name}",
    (
        "https://raw.githubusercontent.com/{owner}/{repo}/"
        "master/completions/{name}.zsh"
    ),
    (
        "https://raw.githubusercontent.com/{owner}/{repo}/"
        "master/completions/_{name}.zsh"
    ),
    "https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash",
    # generic fallback to _name at github root for projects that put completions there
    "https://raw.githubusercontent.com/{owner}/{repo}/master/_{name}",
]

# Per-tool targeted raw URLs (explicit paths) for better discovery.
PER_TOOL_URLS = {
    "ripgrep": [
        ("https://raw.githubusercontent.com/BurntSushi/ripgrep/" "master/complete/_rg"),
        (
            "https://raw.githubusercontent.com/BurntSushi/ripgrep/"
            "master/completions/_rg"
        ),
    ],
    "cargo": [
        (
            "https://raw.githubusercontent.com/rust-lang/cargo/"
            "master/contrib/completion/cargo.zsh"
        ),
        (
            "https://raw.githubusercontent.com/rust-lang/cargo/"
            "master/src/etc/cargo-zsh-completion.sh"
        ),
    ],
    "rustc": [
        (
            "https://raw.githubusercontent.com/rust-lang/rust/"
            "master/src/etc/rustc-completions.zsh"
        ),
    ],
    "gh": [
        ("https://raw.githubusercontent.com/cli/cli/" "trunk/completions/gh.zsh"),
        ("https://raw.githubusercontent.com/cli/cli/" "master/completions/gh.zsh"),
    ],
    "copilot": [
        (
            "https://raw.githubusercontent.com/github/copilot-cli/"
            "main/completions/copilot.zsh"
        ),
        (
            "https://raw.githubusercontent.com/github/copilot-cli/"
            "main/src/completion/copilot.zsh"
        ),
    ],
    "rg": [
        ("https://raw.githubusercontent.com/BurntSushi/ripgrep/" "master/complete/_rg"),
    ],
    "clang": [
        (
            "https://raw.githubusercontent.com/llvm/llvm-project/"
            "main/clang/tools/clang-completion/_clang"
        ),
    ],
    "g++": [
        (
            "https://raw.githubusercontent.com/scop/bash-completion/"
            "master/completions/gcc"
        )
    ],
}


def try_fetch(url):
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            if r.status == 200:
                return r.read().decode("utf-8")
    except Exception:
        return None


def generate_from_help(name, timeout=3):
    """Try to derive completion content by running tool's help output locally.

    Returns generated completion content string or None.
    """
    # Find the executable on PATH
    exe = shutil.which(name)
    if not exe:
        # try name with + escaped (g++, clang++)
        exe = shutil.which(name.replace("+", ""))
        if not exe:
            return None

    # Try common help forms
    help_cmds = [[exe, "--help"], [exe, "-h"], [exe, "help"]]
    out = ""
    for cmd in help_cmds:
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            if p.returncode == 0 or p.stdout:
                out = p.stdout.strip() or p.stderr.strip()
                if out:
                    break
        except Exception:
            continue

    if not out:
        return None

    # Parse options and subcommands
    import re

    opts = set()
    cmds = []

    # matches --long-option or -s
    for match in re.finditer(r"(?P<option>--?[A-Za-z0-9][-A-Za-z0-9_=]*)", out):
        opts.add(match.group("option"))

    # Find 'Commands:' sections or lines that start with whitespace and a word then two spaces
    # Match commands lines that either begin with a command followed by two
    # spaces, or command followed by whitespace and a dash (common help layouts
    # across many projects). Keep the pattern split across two literals to
    # satisfy linters' max-line-length limits.
    CMD_RE = r"^\s{0,4}([a-z0-9][a-z0-9_\-]*)" r"(?:\s{2,}|\s+-)"
    for line in out.splitlines():
        m = re.match(CMD_RE, line, re.I)
        if m:
            cmd = m.group(1).strip()
            if cmd and not cmd.startswith("-"):
                cmds.append(cmd)

    # Construct a zsh completion snippet
    parts = [
        "#!/usr/bin/env bash",
        f"# Auto-generated completion for {name} (from --help output)",
        "#compdef %s" % name,
        "",
    ]

    if cmds:
        # create a commands list
        parts.append("local -a commands")
        parts.append("commands=(")
        for c in sorted(set(cmds))[:200]:
            parts.append(f"  '{c}:{c} subcommand'")
        parts.append(")")
        parts.append("_describe 'command' commands && return 0")

    if opts:
        parts.append("local -a opts")
        parts.append("opts=(")
        for o in sorted(opts):
            # skip single-letter grouped options without description
            parts.append(f"  '{o}:{o} option'")
        parts.append(")")
        parts.append("_describe 'option' opts && return 0")

    # fallback to files
    parts.append("_files")
    parts.append("")
    return "\n".join(parts)


def ensure_out_dir():
    os.makedirs(OUT_DIR, exist_ok=True)


def save(name, content):
    fname = os.path.join(OUT_DIR, f"_{name}")
    if os.path.exists(fname):
        with open(fname, "r", encoding="utf-8") as f:
            existing = f.read()
        if existing == content:
            print(f"SKIP: _{name} already exists (identical)")
            return False
        # If generated content looks significantly richer, overwrite but keep backup
        if len(content) > len(existing) + 30:
            bak = fname + ".bak"
            with open(bak, "w", encoding="utf-8") as bf:
                bf.write(existing)
            with open(fname, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OVERWROTE: {fname} (backup at {bak})")
            return True
        else:
            gen_name = fname + ".generated"
            with open(gen_name, "w", encoding="utf-8") as gf:
                gf.write(content)
            print(f"WROTE GENERATED: {gen_name} (existing _{name} kept)")
            return True
    with open(fname, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"WROTE: {fname}")
    return True


def main(names):
    ensure_out_dir()
    results = {}
    for name in names:
        got = False
        # try zsh-completions and ohmyzsh
        # try the primary set first (zsh-completions / ohmyzsh / bash-completion)
        for tmpl in SOURCES[:8]:
            # skip owner/repo templates in the first pass
            if "{owner" in tmpl or "{repo" in tmpl:
                continue
            url = tmpl.format(name=name)
            content = try_fetch(url)
            if content:
                print(f"FOUND upstream for {name} -> {url}")
                saved = save(name, content)
                results[name] = (url, saved)
                got = True
                break

        if got:
            continue

        # try alternate names / filename encodings
        alts = ALTERNATES.get(name, [name])
        for alt in alts:
            for tmpl in SOURCES[:8]:
                if "{owner" in tmpl or "{repo" in tmpl:
                    continue
                try_name = alt
                # url-encode '+' in names for safe requests
                try_name_esc = try_name.replace("+", "%2B")
                url = tmpl.format(name=try_name_esc)
                content = try_fetch(url)
                if content:
                    print(f"FOUND upstream for {name} (via {try_name}) -> {url}")
                    saved = save(name, content)
                    results[name] = (url, saved)
                    got = True
                    break
            if got:
                break

        # a small heuristic: check for repo named after cli in common orgs
        # try lookups in some likely owners (git, rust-lang, microsoft, npm)
        attempts = [
            ("git", "git"),
            ("ripgrep", "ripgrep"),
            ("rust-lang", "cargo"),
            ("rust-lang", "rust"),
            # Try some known owners / repos for specific tools
            ("BurntSushi", "ripgrep"),
            ("cli", "cli"),
            ("github", "copilot-cli"),
            ("rust-lang", "cargo"),
            ("rust-lang", "rust"),
            ("llvm", "llvm-project"),
            ("psf", "black"),
            ("microsoft", "vcpkg"),
            ("nodejs", "node"),
            ("npm", "cli"),
            ("microsoft", name),
            ("Homebrew", name),
            ("docker", name),
        ]
        for owner, repo in attempts:
            url = SOURCES[2].format(owner=owner, repo=repo, name=name)
            content = try_fetch(url)
            if content:
                print(f"FOUND (fallback) for {name} -> {url}")
                saved = save(name, content)
                results[name] = (url, saved)
                got = True
                break

        # If nothing remote was found, attempt to generate a completion from
        # the local program's --help output where possible.
        if not got:
            generated = generate_from_help(name)
            if generated:
                print(f"GENERATED completion for {name} from local --help")
                save(name, generated)
                results[name] = (f"generated:{name}", True)
                got = True

        if not got:
            print(f"NOT FOUND: {name}")
            results[name] = (None, False)

    return results


if __name__ == "__main__":
    names = sys.argv[1:] or DEFAULTS
    main(names)
