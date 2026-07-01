#!/data/data/com.termux/files/usr/bin/bash
#
# install.sh — Native Claude Code for Termux (aarch64). No proot.
#
# Reproduces a from-scratch native install:
#   1. glibc runtime + loader-patcher + linker (Termux glibc repo)
#   2. an LD_PRELOAD DNS shim that replaces proot's only job
#   3. a self-updating / self-healing launcher
#   4. bootstrap of the official Claude Code linux-arm64 binary
#
# Installs the RUNTIME ONLY — no memories, no plugins, no settings, no tokens.
# Your ~/.claude is created fresh by Claude on first run.
#
set -euo pipefail

say(){ printf '\033[1;36m[claude-native]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[claude-native] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
GL="$PREFIX/glibc"
GLIBC_LD="$GL/lib/ld-linux-aarch64.so.1"
SHIM="$PREFIX/lib/claude-resolvfix.so"
RESOLV="$PREFIX/etc/resolv.conf"
LAUNCHER="$PREFIX/bin/claude"
VERSIONS_DIR="$HOME_DIR/.local/share/claude/versions"
RAW="https://raw.githubusercontent.com/Thr45hx/claude-code-termux-native/main"

# 0) sanity ------------------------------------------------------------------
[ -d "$PREFIX" ] || die "Not a Termux environment ($PREFIX missing)."
case "$(uname -m)" in
  aarch64|arm64) ;;
  *) die "arm64/aarch64 only (found '$(uname -m)'): the Claude binary, glibc and shim are all arm64." ;;
esac

# Resolve the source dir. When piped via `curl | bash` the sibling files aren't
# on disk, so stage claude + fix_resolv.c from the repo into a temp dir.
SRC_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [ -z "$SRC_DIR" ] || [ ! -f "$SRC_DIR/fix_resolv.c" ] || [ ! -f "$SRC_DIR/claude" ]; then
  command -v curl >/dev/null 2>&1 || die "curl needed to fetch source files."
  SRC_DIR="$(mktemp -d)"
  say "Fetching source files from $RAW …"
  curl -fsSL "$RAW/fix_resolv.c" -o "$SRC_DIR/fix_resolv.c" || die "could not fetch fix_resolv.c"
  curl -fsSL "$RAW/claude"       -o "$SRC_DIR/claude"       || die "could not fetch claude launcher"
fi

# 1) base packages (bionic) --------------------------------------------------
say "Updating package lists…"
pkg update -y >/dev/null 2>&1 || true
say "Installing base packages: clang curl jq…"
pkg install -y clang curl jq >/dev/null || die "pkg install (clang/curl/jq) failed."

# 2) glibc runtime + patchelf + binutils -------------------------------------
if [ ! -f "$GLIBC_LD" ] || [ ! -x "$GL/bin/patchelf" ] || [ ! -x "$GL/bin/ld" ]; then
  say "Enabling the Termux glibc repository…"
  pkg install -y glibc-repo >/dev/null || die "could not install glibc-repo."
  pkg update -y >/dev/null 2>&1 || true
  say "Installing glibc runtime, patchelf-glibc, binutils-glibc…"
  pkg install -y glibc patchelf-glibc binutils-glibc >/dev/null || die "glibc package install failed."
fi
[ -f "$GLIBC_LD" ]        || die "glibc loader missing: $GLIBC_LD"
[ -x "$GL/bin/patchelf" ] || die "patchelf missing: $GL/bin/patchelf"
[ -x "$GL/bin/ld" ]       || die "glibc ld missing: $GL/bin/ld"

# 3) DNS redirect target -----------------------------------------------------
# Termux /etc is a read-only symlink to /system/etc, so /etc/resolv.conf can't
# exist. The shim redirects reads of it to $RESOLV, which must hold nameservers.
if [ ! -s "$RESOLV" ] || ! grep -q '^nameserver' "$RESOLV" 2>/dev/null; then
  say "Writing $RESOLV (Cloudflare + Google DNS)…"
  mkdir -p "$(dirname "$RESOLV")"
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$RESOLV"
fi

# 4) build the DNS shim ------------------------------------------------------
say "Compiling claude-resolvfix.so…"
build="$(mktemp -d)"
cp "$SRC_DIR/fix_resolv.c" "$build/fix_resolv.c"
(
  cd "$build"
  clang --target=aarch64-linux-gnu -fPIC -O2 -fno-stack-protector -c fix_resolv.c -o fix_resolv.o
  "$GL/bin/ld" -shared -o libclaude-resolvfix.so fix_resolv.o -L"$GL/lib" -l:libc.so.6 -l:libdl.so.2
) || { rm -rf "$build"; die "shim compile/link failed."; }
install -m644 "$build/libclaude-resolvfix.so" "$SHIM"
rm -rf "$build"
[ -f "$SHIM" ] || die "shim not installed."

# 5) install the launcher ----------------------------------------------------
if [ -f "$LAUNCHER" ] && ! grep -q claude-resolvfix "$LAUNCHER" 2>/dev/null; then
  say "Backing up existing launcher → ${LAUNCHER}.bak"
  cp "$LAUNCHER" "$LAUNCHER.bak"
fi
say "Installing launcher → $LAUNCHER"
install -m755 "$SRC_DIR/claude" "$LAUNCHER"
mkdir -p "$VERSIONS_DIR"

# 6) bootstrap the official Claude Code binary -------------------------------
# First launch downloads the latest linux-arm64 build from downloads.claude.ai,
# sha256-verifies it against the release manifest, patchelfs its interpreter to
# glibc's loader, and smoke-tests it against Android seccomp crashes.
say "Bootstrapping the latest Claude Code binary…"
if "$LAUNCHER" --version >/dev/null 2>&1; then
  say "Installed: $("$LAUNCHER" --version 2>/dev/null | head -1)"
else
  say "Launcher is in place; run 'claude' once you're online to fetch the binary."
fi

echo
say "Native install complete — no proot in the runtime path."
say "Launch with:  claude"
