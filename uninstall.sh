#!/data/data/com.termux/files/usr/bin/bash
#
# uninstall.sh — remove the native launcher + DNS shim.
# Leaves glibc, ~/.claude (your config/sessions) and downloaded binaries alone.
#
set -euo pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
say(){ printf '\033[1;36m[claude-native]\033[0m %s\n' "$*"; }

say "Removing DNS shim…";  rm -f "$PREFIX/lib/claude-resolvfix.so"
if [ -f "$PREFIX/bin/claude.bak" ]; then
  say "Restoring previous launcher from claude.bak…"
  mv -f "$PREFIX/bin/claude.bak" "$PREFIX/bin/claude"
else
  say "Removing launcher…"; rm -f "$PREFIX/bin/claude"
fi
say "Done."
say "Kept: glibc runtime, ~/.claude, ~/.local/share/claude (binaries)."
say "To remove those too:  rm -rf ~/.claude ~/.local/share/claude  &&  pkg uninstall glibc-repo"
