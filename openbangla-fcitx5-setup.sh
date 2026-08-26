#!/usr/bin/env bash

# Configure OpenBangla Keyboard's Fcitx5 engine on Omarchy/Hyprland.
# Run as the desktop user (not root): ./openbangla-fcitx5-setup.sh

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/openbangla-fcitx5/backups/$TIMESTAMP"
readonly MANAGED_BEGIN="-- BEGIN openbangla-fcitx5 (managed by $SCRIPT_NAME)"
readonly MANAGED_END="-- END openbangla-fcitx5 (managed by $SCRIPT_NAME)"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v pacman >/dev/null || die "This script requires Arch Linux/pacman."
command -v omarchy >/dev/null || die "This script requires Omarchy."
command -v fcitx5 >/dev/null || die "Fcitx5 is not installed. Update Omarchy first."
command -v gdbus >/dev/null || die "gdbus (glib2) is required to configure the Fcitx5 input method group."
(( EUID != 0 )) || die "Run this as the logged-in desktop user, not as root."
# The AUR build below ends with `sudo pacman -U`, which needs to prompt for
# your password on a real TTY. Without one, sudo times out mid-build and this
# script dies right after the AUR step, leaving the input-method config below
# it (profile, F12 binding, environment) never written.
[[ -t 0 && -t 1 ]] || die "Run this in an interactive terminal, not through a non-interactive/piped shell (sudo needs a TTY for the AUR package build)."

backup_file() {
  local source="$1" relative destination
  [[ -e "$source" || -L "$source" ]] || return 0
  relative="${source#/}"
  destination="$BACKUP_ROOT/$relative"
  mkdir -p "${destination%/*}"
  cp -a -- "$source" "$destination"
}

write_file() {
  local destination="$1" mode="${2:-0644}"
  mkdir -p "${destination%/*}"
  install -m "$mode" /dev/stdin "$destination"
}

append_flag() {
  local file="$1" flag="$2"
  mkdir -p "${file%/*}"
  touch "$file"
  if ! awk -v wanted="$flag" '$0 == wanted { found=1 } END { exit !found }' "$file"; then
    printf '%s\n' "$flag" >> "$file"
  fi
}

# Preserve an INI file while setting one key in one section.
set_ini_key() {
  local file="$1" section="$2" key="$3" value="$4" temporary
  mkdir -p "${file%/*}"
  touch "$file"
  temporary="$(mktemp)"
  awk -v wanted_section="[$section]" -v wanted_key="$key" -v wanted_value="$value" '
    BEGIN { in_section=0; section_seen=0; key_seen=0 }
    /^\[/ {
      if (in_section && !key_seen) print wanted_key "=" wanted_value
      in_section=($0 == wanted_section)
      if (in_section) { section_seen=1; key_seen=0 }
      print
      next
    }
    in_section && $0 ~ "^[[:space:]]*" wanted_key "[[:space:]]*=" {
      if (!key_seen) print wanted_key "=" wanted_value
      key_seen=1
      next
    }
    { print }
    END {
      if (in_section && !key_seen) print wanted_key "=" wanted_value
      if (!section_seen) {
        if (NR > 0) print ""
        print wanted_section
        print wanted_key "=" wanted_value
      }
    }
  ' "$file" > "$temporary"
  install -m 0644 "$temporary" "$file"
  rm -f -- "$temporary"
}

remove_managed_lua_block() {
  local file="$1" temporary
  [[ -f "$file" ]] || return 0
  temporary="$(mktemp)"
  awk -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" '
    $0 == begin { managed=1; next }
    $0 == end { managed=0; next }
    !managed { print }
  ' "$file" > "$temporary"
  install -m 0644 "$temporary" "$file"
  rm -f -- "$temporary"
}

audit() {
  log "Pre-change audit"
  printf 'Omarchy: '; omarchy version 2>&1 || true
  printf 'Kernel: '; uname -r
  printf 'Session: %s / %s\n' "${XDG_CURRENT_DESKTOP:-unknown}" "${XDG_SESSION_TYPE:-unknown}"

  printf '\nInstalled input-method packages:\n'
  pacman -Q 2>/dev/null | awk 'BEGIN{IGNORECASE=1} $1 ~ /^(fcitx|ibus|openbangla|avro)/ {print}' || true

  printf '\nInput-method processes:\n'
  ps -eo pid,comm,args | awk '$2 ~ /^(fcitx5|ibus-daemon|openbangla)/ {print}' || true

  printf '\nRelevant environment:\n'
  env | sort | awk -F= '$1 ~ /^(GTK_IM_MODULE|QT_IM_MODULE|QT_IM_MODULES|XMODIFIERS|INPUT_METHOD|SDL_IM_MODULE|GLFW_IM_MODULE|ELECTRON_OZONE_PLATFORM_HINT)$/ {print}' || true

  printf '\nExisting F12/input-method references:\n'
  rg -n -i 'F12|fcitx|ibus|openbangla|GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS' \
    "$HOME/.config/hypr" "$HOME/.config/fcitx5" "$HOME/.config/environment.d" \
    "$HOME/.profile" "$HOME/.xprofile" "$HOME/.zprofile" "$HOME/.pam_environment" \
    2>/dev/null || true
}

audit

if [[ "${1:-}" == "--audit" ]]; then
  exit 0
elif (($#)); then
  die "Usage: $SCRIPT_NAME [--audit]"
fi

log "Installing the Fcitx5 frontend modules and configuration tool"
omarchy pkg add fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool noto-fonts

log "Removing conflicting IBus/OpenBangla packages, if present"
conflicting_packages=(
  ibus ibus-avro ibus-avro-git
  ibus-openbangla ibus-openbangla-git
  openbangla-keyboard openbangla-keyboard-bin openbangla-keyboard-git
  fcitx5-openbangla-git
)
installed_conflicts=()
for package in "${conflicting_packages[@]}"; do
  pacman -Q "$package" >/dev/null 2>&1 && installed_conflicts+=("$package")
done
if ((${#installed_conflicts[@]})); then
  omarchy pkg drop "${installed_conflicts[@]}"
fi

command -v yay >/dev/null || die "The Fcitx5 OpenBangla engine requires yay/AUR access."
log "Installing OpenBangla's native Fcitx5 engine"
omarchy pkg aur add openbangla-keyboard-fcitx-git

descriptor=""
for candidate in \
  /usr/share/fcitx5/inputmethod/openbangla.conf \
  /usr/local/share/fcitx5/inputmethod/openbangla.conf; do
  if [[ -f "$candidate" ]]; then
    descriptor="$candidate"
    break
  fi
done
[[ -n "$descriptor" ]] || die "OpenBangla installed, but its Fcitx5 input-method descriptor was not found."
OPENBANGLA_IM="${descriptor##*/}"
readonly OPENBANGLA_IM="${OPENBANGLA_IM%.conf}"

log "Creating timestamped backups before editing user configuration"
files_to_change=(
  "$HOME/.config/fcitx5/config"
  "$HOME/.config/fcitx5/profile"
  "$HOME/.config/environment.d/90-openbangla-fcitx5.conf"
  "$HOME/.config/gtk-3.0/settings.ini"
  "$HOME/.config/gtk-4.0/settings.ini"
  "$HOME/.config/hypr/bindings.lua"
  "$HOME/.config/chromium-flags.conf"
  "$HOME/.config/brave-flags.conf"
  "$HOME/.config/brave-origin-beta-flags.conf"
  "$HOME/.config/chrome-flags.conf"
  "$HOME/.config/code-flags.conf"
  "$HOME/.config/electron-flags.conf"
  "$HOME/.config/autostart/org.fcitx.Fcitx5.desktop"
  "$HOME/.config/ibus"
)
for file in "${files_to_change[@]}"; do backup_file "$file"; done
printf 'Backups: %s\n' "$BACKUP_ROOT"

log "Disabling IBus state and autostart conflicts"
while read -r unit _; do
  [[ -n "$unit" ]] || continue
  systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
done < <(systemctl --user list-unit-files --no-legend 2>/dev/null | awk 'tolower($1) ~ /ibus/ {print}')
pkill -x ibus-daemon 2>/dev/null || true

# The stale bus files can advertise obsolete IBus addresses. Keep them in the
# timestamped backup, then move the live directory aside instead of deleting it.
if [[ -d "$HOME/.config/ibus" ]]; then
  mv -- "$HOME/.config/ibus" "$HOME/.config/ibus.disabled.$TIMESTAMP"
fi

# Omarchy supervises Fcitx5 with a graphical-session systemd unit. Hide the
# generic XDG autostart entry so a second unsupervised instance cannot race it.
write_file "$HOME/.config/autostart/org.fcitx.Fcitx5.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Fcitx 5 (managed by Omarchy systemd service)
Hidden=true
EOF

# English and OpenBangla are added to the input method group further down,
# once Fcitx5 is actually running (see "Configuring the input method group"
# below). Fcitx5 owns ~/.config/fcitx5/profile as live, running-daemon state:
# a hand-written profile that renames/repopulates the group is silently
# discarded and rewritten back to a bare "keyboard-us"-only default the next
# time Fcitx5 starts, because the group's identity isn't only tracked by that
# file's text. The group must instead be configured through Fcitx5's own
# org.fcitx.Fcitx.Controller1 D-Bus interface (the same one fcitx5-configtool
# uses), which is what actually persists.

# F12 is handled by Hyprland below, which makes the switch truly global. Empty
# Fcitx trigger keys prevent the same keystroke from toggling twice in clients.
write_file "$HOME/.config/fcitx5/config" <<'EOF'
[Hotkey]
EnumerateWithTriggerKeys=False
EnumerateForwardKeys=
EnumerateBackwardKeys=
EnumerateSkipFirst=False
ModifierOnlyKeyTimeout=250

[Hotkey/TriggerKeys]

[Hotkey/AltTriggerKeys]

[Hotkey/EnumerateGroupForwardKeys]

[Hotkey/EnumerateGroupBackwardKeys]

[Hotkey/ActivateKeys]

[Hotkey/DeactivateKeys]

[Hotkey/PrevPage]
0=Up

[Hotkey/NextPage]
0=Down

[Hotkey/PrevCandidate]
0=Shift+Tab

[Hotkey/NextCandidate]
0=Tab

[Hotkey/TogglePreedit]
0=Control+Alt+P

[Behavior]
ActiveByDefault=False
resetStateWhenFocusIn=No
ShareInputState=All
PreeditEnabledByDefault=True
ShowInputMethodInformation=True
showInputMethodInformationWhenFocusIn=False
CompactInputMethodInformation=True
ShowFirstInputMethodInformation=True
DefaultPageSize=5
OverrideXkbOption=False
CustomXkbOption=
EnabledAddons=
DisabledAddons=
PreloadInputMethod=True
AllowInputMethodForPassword=False
ShowPreeditForPassword=False
AutoSavePeriod=30
EOF

log "Configuring login environment for Wayland, XWayland, Qt, SDL, and kitty"
# GTK_IM_MODULE is intentionally left unset here (not set to an empty value):
# systemd's environment.d parser (systemd 261+) rejects a bare `KEY=` with no
# right-hand side as invalid syntax and drops the whole line, so an explicit
# empty assignment silently accomplishes nothing anyway. Leaving it unset lets
# native GTK3/4 use Wayland text-input-v3; gtk-3.0/gtk-4.0 settings below
# still select Fcitx for X11/XWayland.
write_file "$HOME/.config/environment.d/90-openbangla-fcitx5.conf" <<'EOF'
INPUT_METHOD=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
# kitty's X11 IME frontend speaks the IBus protocol; Fcitx5 provides that
# protocol itself. This does not start or require ibus-daemon.
GLFW_IM_MODULE=ibus
EOF

set_ini_key "$HOME/.config/gtk-3.0/settings.ini" Settings gtk-im-module fcitx
set_ini_key "$HOME/.config/gtk-4.0/settings.ini" Settings gtk-im-module fcitx

log "Adding native Wayland IME flags for Chromium-family and Electron applications"
browser_flag_files=(
  "$HOME/.config/chromium-flags.conf"
  "$HOME/.config/brave-flags.conf"
  "$HOME/.config/brave-origin-beta-flags.conf"
  "$HOME/.config/chrome-flags.conf"
)
for file in "${browser_flag_files[@]}"; do
  append_flag "$file" --ozone-platform=wayland
  append_flag "$file" --enable-wayland-ime
done

for file in "$HOME/.config/code-flags.conf" "$HOME/.config/electron-flags.conf"; do
  append_flag "$file" --ozone-platform=wayland
  append_flag "$file" --enable-wayland-ime
done

log "Binding CTRL + SPACE globally without replacing other Omarchy/Hyprland settings"
bindings_file="$HOME/.config/hypr/bindings.lua"
mkdir -p "${bindings_file%/*}"
touch "$bindings_file"
remove_managed_lua_block "$bindings_file"
{
  printf '\n%s\n' "$MANAGED_BEGIN"
  printf '%s\n' '# CTRL + SPACE is not bound by Omarchy'"'"'s defaults (only SUPER+SPACE and'
  printf '%s\n' '# other SUPER-combos are). Keep the explicit unbind so a future Omarchy'
  printf '%s\n' '# default cannot shadow this global toggle.'
  printf '%s\n' 'hl.unbind("CTRL + SPACE")'
  printf '%s\n' 'o.bind("CTRL + SPACE", "Toggle English/Bangla input", "fcitx5-remote -t")'
  printf '%s\n' "$MANAGED_END"
} >> "$bindings_file"

log "Enabling Omarchy's supervised Fcitx5 service"
systemctl --user daemon-reload
systemctl --user enable omarchy-fcitx5.service
systemctl --user restart omarchy-fcitx5.service

log "Reloading and validating Hyprland"
hyprctl reload
config_errors="$(hyprctl configerrors 2>&1 || true)"
printf '%s\n' "$config_errors"
if [[ -n "${config_errors//[[:space:]]/}" && "$config_errors" != *"no errors"* ]]; then
  die "Hyprland reported configuration errors. Restore from $BACKUP_ROOT before logging out."
fi

log "Verifying packages, engine, daemon, and English/Bangla state transitions"
for package in fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool openbangla-keyboard-fcitx-git; do
  pacman -Q "$package" >/dev/null || die "Required package missing: $package"
done

systemctl --user is-enabled --quiet omarchy-fcitx5.service || die "Fcitx5 service is not enabled."
systemctl --user is-active --quiet omarchy-fcitx5.service || die "Fcitx5 service is not running."

log "Configuring English and OpenBangla (Avro Phonetic) as the only input pair"
readonly FCITX_IFACE="org.fcitx.Fcitx.Controller1"
fcitx_dbus() {
  gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller \
    --method "$FCITX_IFACE.$1" "${@:2}"
}
available_ims="$(fcitx_dbus AvailableInputMethods)"
[[ "$available_ims" == *"'$OPENBANGLA_IM'"* ]] || die "Fcitx5 does not list '$OPENBANGLA_IM' as an available input method."
current_group="$(fcitx_dbus CurrentInputMethodGroup | sed -n "s/^('\\(.*\\)',)\$/\\1/p")"
[[ -n "$current_group" ]] || die "Could not determine the current Fcitx5 input method group."
fcitx_dbus SetInputMethodGroupInfo "$current_group" "us" \
  "[('keyboard-us', ''), ('$OPENBANGLA_IM', '')]" >/dev/null

fcitx5-remote -r
sleep 1
fcitx5-remote -c
fcitx5-remote -t
[[ "$(fcitx5-remote)" == "2" ]] || die "Fcitx5 did not enter Bangla/active state."
current_im="$(fcitx5-remote -n)"
[[ "$current_im" == "$OPENBANGLA_IM" ]] || die "Active input method is '$current_im', expected '$OPENBANGLA_IM'."
fcitx5-remote -t
[[ "$(fcitx5-remote)" == "1" ]] || die "Fcitx5 did not return to English/inactive state."

for package in "${conflicting_packages[@]}"; do
  pacman -Q "$package" >/dev/null 2>&1 && die "A conflicting package is still installed: $package"
done
pgrep -x ibus-daemon >/dev/null 2>&1 && die "ibus-daemon is still running."

printf '\nSetup complete.\n'
printf 'Backups: %s\n' "$BACKUP_ROOT"
printf 'Final state: English (F12 switches to OpenBangla/Avro; F12 switches back).\n'
printf 'Log out and back in once so every already-running application inherits the corrected environment.\n'
printf 'After login, fully restart Firefox, Chromium/Brave/Chrome, VS Code, Electron apps, and terminals before testing.\n'
