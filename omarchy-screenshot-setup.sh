#!/usr/bin/env bash
# Sets up the screenshot workflow on an Omarchy machine:
#   CTRL+ALT+SHIFT+S  (and Print)  -> region screenshot + edit (omarchy-capture-screenshot)
#   CTRL+ALT+SHIFT+U               -> upload latest screenshot to catbox.moe, copy link
# Safe to re-run (idempotent). Supports Lua (~/.config/hypr/bindings.lua) and
# legacy (~/.config/hypr/bindings.conf) Omarchy configs.

set -euo pipefail

HYPR_DIR="$HOME/.config/hypr"
BIN_DIR="$HOME/.local/bin"
MARK_BEGIN="# >>> screenshot-setup >>>"
MARK_END="# <<< screenshot-setup <<<"
LUA_MARK_BEGIN="-- >>> screenshot-setup >>>"
LUA_MARK_END="-- <<< screenshot-setup <<<"

echo "==> Checking dependencies"
command -v omarchy-capture-screenshot >/dev/null 2>&1 || {
  echo "omarchy-capture-screenshot not found - is this an Omarchy install?" >&2
  exit 1
}
missing=()
for c in curl wl-copy notify-send; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if ((${#missing[@]})); then
  echo "Installing missing tools: ${missing[*]}"
  pkgs=()
  for c in "${missing[@]}"; do
    case "$c" in
      curl) pkgs+=(curl) ;;
      wl-copy) pkgs+=(wl-clipboard) ;;
      notify-send) pkgs+=(libnotify) ;;
    esac
  done
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"
fi

echo "==> Installing omarchy-upload-screenshot to $BIN_DIR"
mkdir -p "$BIN_DIR"
cat >"$BIN_DIR/omarchy-upload-screenshot" <<'UPLOAD'
#!/usr/bin/env bash

set -euo pipefail

upload_endpoint="https://catbox.moe/user/api.php"
picture_dir="${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-"$HOME/Pictures"}}"

if [[ ! -d "$picture_dir" ]]; then
	notify-send -u critical "Screenshot upload failed" "Pictures directory does not exist: $picture_dir"
	exit 1
fi

latest_file="$(
	find "$picture_dir" -maxdepth 1 -type f \
		\( -name 'screenshot-*.png' -o -name 'screenshot-*.jpg' -o -name 'screenshot-*.jpeg' -o -name 'screenshot-*.webp' \) \
		-printf '%T@\t%p\n' |
		sort -nr |
		head -n 1 |
		cut -f2-
)"

if [[ -z "$latest_file" ]]; then
	notify-send -u critical "Screenshot upload failed" "No saved screenshot was found in $picture_dir"
	exit 1
fi

if ! command -v wl-copy >/dev/null 2>&1; then
	notify-send -u critical "Screenshot upload failed" "wl-copy is required to copy the share link"
	exit 1
fi

response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT

if ! curl --fail-with-body --silent --show-error --max-time 120 \
	-F "reqtype=fileupload" \
	-F "fileToUpload=@$latest_file" \
	"$upload_endpoint" >"$response_file"; then
	error_message="$(tr '\n' ' ' <"$response_file" | cut -c1-180)"
	notify-send -u critical "Screenshot upload failed" "${error_message:-The upload request failed}"
	exit 1
fi

share_url="$(tr -d '[:space:]' <"$response_file")"
if [[ ! "$share_url" =~ ^https://files\.catbox\.moe/[A-Za-z0-9._-]+$ ]]; then
	notify-send -u critical "Screenshot upload failed" "The upload service returned an invalid link"
	exit 1
fi

printf '%s' "$share_url" | wl-copy
notify-send "Screenshot uploaded" "Link copied to clipboard: $share_url"
UPLOAD
chmod +x "$BIN_DIR/omarchy-upload-screenshot"

mkdir -p "$HYPR_DIR"
LUA_CFG="$HYPR_DIR/bindings.lua"
CONF_CFG="$HYPR_DIR/bindings.conf"

# Prefer Lua config if present (new Omarchy), else legacy conf.
if [[ -f $LUA_CFG || -f $HYPR_DIR/hyprland.lua ]]; then
  CFG="$LUA_CFG"
  touch "$CFG"
  if grep -qF "$LUA_MARK_BEGIN" "$CFG"; then
    echo "==> Keybindings already present in $CFG (skipping)"
  else
    echo "==> Adding keybindings to $CFG"
    cp "$CFG" "$CFG.bak.$(date +%s)"
    cat >>"$CFG" <<LUA

$LUA_MARK_BEGIN
hl.unbind("CTRL + ALT + SHIFT + S")
o.bind("CTRL + ALT + SHIFT + S", "Screenshot region + edit", "omarchy-capture-screenshot")

-- Override Omarchy's default Print screenshot binding.
hl.unbind("PRINT")
o.bind("PRINT", "Screenshot region + edit", "omarchy-capture-screenshot")

hl.unbind("CTRL + ALT + SHIFT + U")
o.bind("CTRL + ALT + SHIFT + U", "Upload latest screenshot", "omarchy-upload-screenshot")

-- Disable default Shift + Print screenshot binding
hl.unbind("SHIFT + PRINT")
$LUA_MARK_END
LUA
  fi
else
  CFG="$CONF_CFG"
  touch "$CFG"
  if grep -qF "$MARK_BEGIN" "$CFG"; then
    echo "==> Keybindings already present in $CFG (skipping)"
  else
    echo "==> Adding keybindings to $CFG"
    cp "$CFG" "$CFG.bak.$(date +%s)"
    cat >>"$CFG" <<CONF

$MARK_BEGIN
unbind = CTRL ALT SHIFT, S
bindd = CTRL ALT SHIFT, S, Screenshot region + edit, exec, omarchy-capture-screenshot
unbind = , PRINT
bindd = , Print, Screenshot region + edit, exec, omarchy-capture-screenshot
unbind = CTRL ALT SHIFT, U
bindd = CTRL ALT SHIFT, U, Upload latest screenshot, exec, omarchy-upload-screenshot
unbind = SHIFT, PRINT
$MARK_END
CONF
  fi
fi

echo "==> Reloading Hyprland"
hyprctl reload >/dev/null 2>&1 || echo "(hyprctl reload failed - log out/in to apply)"

echo
echo "Done."
echo "  CTRL+ALT+SHIFT+S / Print : region screenshot + edit"
echo "  CTRL+ALT+SHIFT+U         : upload latest screenshot, copy link"
