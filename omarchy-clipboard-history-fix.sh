#!/usr/bin/env bash
#
# Fixes Omarchy's built-in clipboard-history manager (Super+Ctrl+V) so that
# selecting an entry actually auto-pastes it into GUI apps, not just
# terminals.
#
# Bug: the stock `omarchy.clipboard` shell plugin always sends Shift+Insert
# to auto-paste a selected history entry. Only terminal emulators bind
# Shift+Insert to paste; GUI apps (browsers, editors, Electron apps, ...)
# only listen for Ctrl+V. So the entry lands on the real clipboard correctly
# (a manual Ctrl+V right after selecting it works) but the automatic
# keypress silently does nothing in anything but a terminal.
#
# Fix: clone the built-in plugin (the supported, update-safe way to
# customize a packaged Omarchy plugin -- see `omarchy plugin clone --help`)
# and point its auto-paste action at a small wrapper script that detects
# whether the focused window is a terminal (the same window-class pattern
# Omarchy's own universal-paste shortcut uses, see
# /usr/share/omarchy/default/hypr/apps/terminals.lua) and sends
# Shift+Insert there, Ctrl+V everywhere else.
#
# Safe to re-run: every step below is idempotent.
#
# Run as the desktop user (not root) on an Omarchy/Hyprland machine:
#   ./omarchy-clipboard-history-fix.sh

set -Eeuo pipefail

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

(( EUID != 0 )) || die "Run this as the logged-in desktop user, not as root."

command -v omarchy >/dev/null 2>&1 || die "This script is for Omarchy only ('omarchy' command not found)."
command -v hyprctl >/dev/null 2>&1 || die "This script is for Omarchy/Hyprland only ('hyprctl' command not found)."
command -v jq >/dev/null 2>&1 || die "This script requires 'jq' (should already ship with Omarchy)."

if ! command -v wtype >/dev/null 2>&1; then
  SUDO=""
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  elif command -v doas >/dev/null 2>&1; then
    SUDO="doas"
  else
    die "This script requires 'sudo' or 'doas' to install 'wtype'."
  fi
  [[ -t 0 && -t 1 ]] || die "Run this in an interactive terminal so the package-install password prompt can be answered."
  log "Installing wtype (used to inject the paste keystroke)"
  $SUDO pacman -S --needed --noconfirm wtype
fi

WRAPPER="$HOME/.local/bin/omarchy-clipboard-paste-smart"

log "Installing the paste wrapper: $WRAPPER"
mkdir -p "${WRAPPER%/*}"
cat > "$WRAPPER" <<'EOF'
#!/bin/bash
# Copies a clipboard-history entry (text or file) and injects the paste
# keystroke into whatever window regains focus once the clipboard panel
# closes.
#
# Why this exists: the stock omarchy-clipboard-paste-{text,file} scripts
# always send Shift+Insert, which only terminals bind to paste -- GUI apps
# (browsers, editors, Electron apps, ...) bind Ctrl+V instead. See
# /usr/share/omarchy/default/hypr/bindings/clipboard.lua for the same
# terminal/GUI split applied to the universal paste shortcut.

set -uo pipefail

kind="${1:-}"
shift || true

case "$kind" in
  text)
    history_index="${1:-}"
    /usr/share/omarchy/bin/omarchy-clipboard-paste-text --copy-only --history-index "$history_index"
    ;;
  file)
    mime="${1:-}"
    path="${2:-}"
    /usr/share/omarchy/bin/omarchy-clipboard-paste-file --copy-only "$mime" "$path"
    ;;
  *)
    echo "Usage: omarchy-clipboard-paste-smart text <history-index> | file <mime> <path>" >&2
    exit 1
    ;;
esac

# Let the panel finish closing and focus return to the target window.
sleep 0.35

class=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty')

if [[ $class =~ ^(Alacritty|kitty|com\.mitchellh\.ghostty|foot|org\.codeberg\.dnkl\.foot|wezterm|org\.omarchy\..*|TUI\..*)$ ]]; then
  wtype -M shift -k Insert -m shift 2>/dev/null || true
else
  wtype -M ctrl -k v -m ctrl 2>/dev/null || true
fi
EOF
chmod +x "$WRAPPER"

log "Locating (or creating) the local clipboard plugin clone"
clone_dir=""
for candidate in "$HOME"/.config/omarchy/plugins/*.clipboard; do
  [[ -f "$candidate/Clipboard.qml" ]] || continue
  clone_dir="$candidate"
  break
done

restarted_shell_for_clone=false
if [[ -z "$clone_dir" ]]; then
  clone_output="$(omarchy plugin clone omarchy.clipboard 2>&1)" || die "Failed to clone the clipboard plugin: $clone_output"
  printf '%s\n' "$clone_output"
  clone_dir="$(sed -n 's/^Cloned .* to \(.*\) and switched to .*/\1/p' <<<"$clone_output")"
  [[ -n "$clone_dir" && -f "$clone_dir/Clipboard.qml" ]] || die "Could not determine the cloned plugin directory from: $clone_output"
  restarted_shell_for_clone=true
else
  log "Found existing clone: $clone_dir"
fi

qml_file="$clone_dir/Clipboard.qml"

log "Patching $qml_file to auto-paste through the terminal/GUI-aware wrapper"
if grep -qF 'omarchy-clipboard-paste-smart' "$qml_file"; then
  log "Already patched -- skipping"
else
  old_file_marker='omarchy-clipboard-paste-file", row.mime, row.path'
  old_text_marker='omarchy-clipboard-paste-text", "--shift-insert", "--history-index"'

  line_file="$(grep -nF "$old_file_marker" "$qml_file" | head -1 | cut -d: -f1)"
  line_text="$(grep -nF "$old_text_marker" "$qml_file" | head -1 | cut -d: -f1)"
  [[ -n "$line_file" ]] || die "Expected image-paste line not found in $qml_file -- the plugin source may have changed upstream; patch it manually."
  [[ -n "$line_text" ]] || die "Expected text-paste line not found in $qml_file -- the plugin source may have changed upstream; patch it manually."

  cp -- "$qml_file" "$qml_file.bak.$(date +%Y%m%d-%H%M%S)"

  new_line_file='      Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/omarchy-clipboard-paste-smart", "file", row.mime, row.path])'
  new_line_text='      Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/omarchy-clipboard-paste-smart", "text", String(row.historyIndex)])'

  awk -v n="$line_file" -v r="$new_line_file" 'NR==n{print r; next} {print}' "$qml_file" > "$qml_file.tmp" && mv "$qml_file.tmp" "$qml_file"
  awk -v n="$line_text" -v r="$new_line_text" 'NR==n{print r; next} {print}' "$qml_file" > "$qml_file.tmp" && mv "$qml_file.tmp" "$qml_file"
fi

log "Reloading the Omarchy shell"
if $restarted_shell_for_clone; then
  # A fresh clone changes which plugin id is enabled/disabled in shell.json;
  # that swap only takes full effect after a shell restart, not a plugin
  # hot-reload.
  omarchy restart shell
else
  omarchy-shell shell rescanPlugins 2>/dev/null || omarchy restart shell
fi

sleep 1
if ! omarchy plugin list 2>/dev/null | grep -q "$(basename "$clone_dir")"'.*enabled'; then
  warn "Could not confirm the clone is enabled -- run 'omarchy plugin list' and 'omarchy restart shell' manually if paste doesn't work."
fi

printf '\nDone.\n'
printf 'Clipboard history: Super+Ctrl+V. Selecting an entry now sends Ctrl+V in GUI apps and Shift+Insert in terminals.\n'
