#!/bin/bash

# Install Flatpak and AppImage application support for Omarchy 4.x.
#
# Everything lands in the user's own home: no file under /usr/share/omarchy is
# touched, so an `omarchy update` cannot clobber it and cannot be clobbered.
#
# Usage: ./install.sh
#
# Honoured overrides (used by the test harness, not needed by hand):
#   OMARCHY_MENU_FILE   menu extension file to merge the rows into
#   PREFIX_BIN          where the commands go        (default ~/.local/bin)
#   PREFIX_LIB          where the shared lib goes    (default ~/.local/lib/omarchy)
#   PREFIX_HOOKS        where the hooks go           (default ~/.config/omarchy/hooks)

set -euo pipefail

SOURCE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

BIN_DIR="${PREFIX_BIN:-$HOME/.local/bin}"
LIB_DIR="${PREFIX_LIB:-$HOME/.local/lib/omarchy}"
HOOKS_DIR="${PREFIX_HOOKS:-$HOME/.config/omarchy/hooks}"
MENU_FILE="${OMARCHY_MENU_FILE:-$HOME/.config/omarchy/extensions/omarchy-menu.jsonc}"

MENU_BLOCK="$SOURCE_DIR/menu/omarchy-menu.jsonc"
MENU_MARKER="// Flatpak and AppImage application support."

# The rows only; the packaged file wraps them in braces so it parses on its own.
menu_rows() {
  sed '1d;$d' "$MENU_BLOCK"
}

install_commands() {
  mkdir -p "$BIN_DIR" "$LIB_DIR"
  install -m 755 "$SOURCE_DIR"/bin/* "$BIN_DIR/"
  install -m 755 "$SOURCE_DIR/lib/omarchy/appimage.sh" "$LIB_DIR/appimage.sh"
  echo "Installed commands in $BIN_DIR"
}

install_hooks() {
  local hook
  mkdir -p "$HOOKS_DIR/post-update.d" "$HOOKS_DIR/post-boot.d"
  for hook in "$SOURCE_DIR"/hooks/*.d/*; do
    install -m 755 "$hook" "$HOOKS_DIR/$(basename "$(dirname "$hook")")/$(basename "$hook")"
  done
  echo "Installed hooks in $HOOKS_DIR"
}

# Splice the rows in ahead of the extension file's closing brace. JSONC tolerates
# the trailing comma the rows end with, which is what makes this safe to append.
merge_menu() {
  if [[ -f $MENU_FILE ]] && grep -qF "$MENU_MARKER" "$MENU_FILE"; then
    echo "Menu rows already present in $MENU_FILE"
    return 0
  fi

  mkdir -p "$(dirname "$MENU_FILE")"

  if [[ ! -f $MENU_FILE ]]; then
    cp "$MENU_BLOCK" "$MENU_FILE"
    echo "Created $MENU_FILE"
    return 0
  fi

  cp -a "$MENU_FILE" "$MENU_FILE.bak.$(date +%Y%m%d-%H%M%S)"

  local close
  close=$(grep -n '^[[:space:]]*}[[:space:]]*$' "$MENU_FILE" | tail -n1 | cut -d: -f1)

  if [[ -z $close ]]; then
    echo "No closing brace found in $MENU_FILE; add the rows from $MENU_BLOCK by hand." >&2
    return 1
  fi

  local merged
  merged=$(mktemp)
  {
    sed -n "1,$((close - 1))p" "$MENU_FILE"
    echo
    menu_rows
    sed -n "$close,\$p" "$MENU_FILE"
  } >"$merged"
  cat "$merged" >"$MENU_FILE"
  rm -f "$merged"

  echo "Merged menu rows into $MENU_FILE (backup alongside it)"
}

install_commands
install_hooks
merge_menu

if [[ -z ${OMARCHY_MENU_FILE:-} ]] && command -v omarchy &>/dev/null; then
  omarchy menu refresh
fi

cat <<'EOF'

Flatpak and AppImage support installed.

  Install > Flatpak > Enable Flatpak     one-time Flatpak + Flathub setup
  Install > Flatpak > Flathub App        search Flathub and install
  Install > AppImage > AppImage File     install a downloaded .AppImage
  Install > AppImage > From GitHub Repo  install and track a release asset
  Install > AppImage > Auto-Update       daily release check (systemd user timer)
  Update  > AppImages                    update tracked AppImages now
  Remove  > Flatpak App / AppImage       uninstall

Run `omarchy-app-entries-refresh` once (or log out and back in) if the app
search selector is already open; it restarts the shell when that is what it
takes to pick up the Flatpak export dirs.
EOF
