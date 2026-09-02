#!/bin/bash

# Remove Flatpak and AppImage application support from Omarchy.
#
# Only the files this repo installed are removed. Apps you installed with it —
# Flatpaks, AppImages in ~/Applications, their launchers — are left alone, as is
# the XDG_DATA_DIRS line in ~/.config/hypr/envs.lua, which other things may now
# depend on. Both are reported so you can undo them yourself if you want to.
#
# Usage: ./uninstall.sh
#
# Honoured overrides (same as install.sh):
#   OMARCHY_MENU_FILE  PREFIX_BIN  PREFIX_LIB  PREFIX_HOOKS

set -euo pipefail

SOURCE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

BIN_DIR="${PREFIX_BIN:-$HOME/.local/bin}"
LIB_DIR="${PREFIX_LIB:-$HOME/.local/lib/omarchy}"
HOOKS_DIR="${PREFIX_HOOKS:-$HOME/.config/omarchy/hooks}"
MENU_FILE="${OMARCHY_MENU_FILE:-$HOME/.config/omarchy/extensions/omarchy-menu.jsonc}"

MENU_MARKER="// Flatpak and AppImage application support."

# The daily release check has to go before its command does.
if [[ -z ${OMARCHY_MENU_FILE:-} ]] && command -v omarchy-appimage-watch &>/dev/null; then
  omarchy-appimage-watch disable --quiet || true
fi

remove_commands() {
  local command
  for command in "$SOURCE_DIR"/bin/*; do
    rm -f "$BIN_DIR/$(basename "$command")"
  done
  rm -f "$LIB_DIR/appimage.sh"
  rmdir "$LIB_DIR" 2>/dev/null || true
  echo "Removed commands from $BIN_DIR"
}

remove_hooks() {
  local hook
  for hook in "$SOURCE_DIR"/hooks/*.d/*; do
    rm -f "$HOOKS_DIR/$(basename "$(dirname "$hook")")/$(basename "$hook")"
  done
  echo "Removed hooks from $HOOKS_DIR"
}

# Drop the marker comment with its two continuation lines and every row this
# repo owns, keyed by id prefix so nothing else in the file can be caught.
strip_menu() {
  if [[ ! -f $MENU_FILE ]]; then
    return 0
  fi

  if ! grep -qF "$MENU_MARKER" "$MENU_FILE"; then
    echo "No menu rows to remove from $MENU_FILE"
    return 0
  fi

  cp -a "$MENU_FILE" "$MENU_FILE.bak.$(date +%Y%m%d-%H%M%S)"

  local stripped
  stripped=$(mktemp)
  awk -v marker="$MENU_MARKER" '
    index($0, marker) { header = 2; next }
    header && $0 ~ /^[[:space:]]*\/\// { header--; next }
    { header = 0 }
    $0 ~ /^[[:space:]]*"(install\.flatpak|install\.appimage|update\.appimage|remove\.flatpak|remove\.appimage)[."]/ { next }
    { print }
  ' "$MENU_FILE" >"$stripped"

  # Drop the single blank line the merge added ahead of the closing brace.
  awk '
    /^[[:space:]]*$/ { blanks[++held] = $0; next }
    {
      first = ($0 ~ /^[[:space:]]*}[[:space:]]*$/) ? 2 : 1
      for (i = first; i <= held; i++) print blanks[i]
      held = 0
      print
    }
    END { for (i = 1; i <= held; i++) print blanks[i] }
  ' "$stripped" >"$stripped.clean"
  cat "$stripped.clean" >"$MENU_FILE"
  rm -f "$stripped" "$stripped.clean"

  echo "Stripped menu rows from $MENU_FILE (backup alongside it)"
}

remove_commands
remove_hooks
strip_menu

if [[ -z ${OMARCHY_MENU_FILE:-} ]] && command -v omarchy &>/dev/null; then
  omarchy menu refresh
fi

cat <<'EOF'

Flatpak and AppImage support removed.

Left in place on purpose:
  ~/Applications and ~/.local/share/applications/appimage-*.desktop
  Flatpak itself and every app installed through it
  the XDG_DATA_DIRS line in ~/.config/hypr/envs.lua

Remove those by hand if you want them gone: `flatpak uninstall --all`, delete
~/Applications, and drop `require("hypr.envs")` from ~/.config/hypr/hyprland.lua.
EOF
