#!/usr/bin/env bash
#
# Configure OpenBangla Keyboard's Fcitx5 engine for Bangla (Avro Phonetic)
# input, on any Linux distribution and desktop environment/window manager.
#
# - Arch Linux with Omarchy + yay: uses the prebuilt AUR package (fast path,
#   fully tested).
# - Everything else (Debian/Ubuntu, Fedora/RHEL, openSUSE, Alpine, or plain
#   Arch without yay/Omarchy): builds OpenBangla's Fcitx5 engine from source
#   the same way the AUR package does (git clone, cargo build for the Riti
#   engine, cmake for the rest). This path needs network access and a C++/
#   Rust toolchain.
#
# Non-Arch package names below are a best-effort mapping across distro
# families -- if a specific one has changed on your distro/version, package
# installs are attempted one at a time with a warning (not a hard failure),
# and the actual build step further down will fail with a concrete, fixable
# error (e.g. a missing header) if something important is really absent.
#
# Also distro/DE-generic:
# - Fcitx5 autostart uses a plain XDG ~/.config/autostart/*.desktop entry
#   (works under systemd's xdg-desktop-autostart integration, GNOME, KDE,
#   XFCE, and most session managers) instead of an Omarchy-specific unit.
# - The global CTRL+SPACE toggle is wired up automatically only on
#   Omarchy/Hyprland; everywhere else this script prints the command
#   (`fcitx5-remote -t`) and example steps to bind it yourself.
# - Login environment variables go through systemd's environment.d when
#   systemd is present, and through ~/.profile / ~/.xprofile otherwise.
#
# Run as the desktop user (not root): ./openbangla-fcitx5-setup.sh

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/openbangla-fcitx5/backups/$TIMESTAMP"
readonly MANAGED_BEGIN_LUA="-- BEGIN openbangla-fcitx5 (managed by $SCRIPT_NAME)"
readonly MANAGED_END_LUA="-- END openbangla-fcitx5 (managed by $SCRIPT_NAME)"
readonly MANAGED_BEGIN_SH="# BEGIN openbangla-fcitx5 (managed by $SCRIPT_NAME)"
readonly MANAGED_END_SH="# END openbangla-fcitx5 (managed by $SCRIPT_NAME)"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

(( EUID != 0 )) || die "Run this as the logged-in desktop user, not as root."
# The install/build steps below prompt for a privileged-escalation password
# and (on non-Arch distros) may run a real compile; both need a real TTY.
[[ -t 0 && -t 1 ]] || die "Run this in an interactive terminal, not through a non-interactive/piped shell."

for tool in git gdbus; do
  command -v "$tool" >/dev/null || die "This script requires '$tool'."
done

SUDO=""
if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
elif command -v doas >/dev/null 2>&1; then
  SUDO="doas"
else
  die "This script requires 'sudo' or 'doas' for privileged operations."
fi

### Package manager detection ###############################################

detect_pkg_manager() {
  if command -v pacman >/dev/null 2>&1; then printf 'pacman'
  elif command -v apt-get >/dev/null 2>&1; then printf 'apt'
  elif command -v dnf >/dev/null 2>&1; then printf 'dnf'
  elif command -v zypper >/dev/null 2>&1; then printf 'zypper'
  elif command -v apk >/dev/null 2>&1; then printf 'apk'
  else printf 'unknown'
  fi
}
readonly PKG_MANAGER="$(detect_pkg_manager)"
[[ "$PKG_MANAGER" != "unknown" ]] || die "No supported package manager found (looked for pacman, apt, dnf, zypper, apk)."

pkg_install() {
  local pkg
  for pkg in "$@"; do
    case "$PKG_MANAGER" in
      pacman) $SUDO pacman -S --needed --noconfirm "$pkg" ;;
      apt)    $SUDO apt-get install -y "$pkg" ;;
      dnf)    $SUDO dnf install -y "$pkg" ;;
      zypper) $SUDO zypper --non-interactive install "$pkg" ;;
      apk)    $SUDO apk add "$pkg" ;;
    esac || warn "Could not install '$pkg' -- the package name may differ on your distro/version. If this package matters, install its equivalent yourself and re-run."
  done
}

pkg_is_installed() {
  case "$PKG_MANAGER" in
    pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
    apt)    dpkg -s "$1" >/dev/null 2>&1 ;;
    dnf)    rpm -q "$1" >/dev/null 2>&1 ;;
    zypper) rpm -q "$1" >/dev/null 2>&1 ;;
    apk)    apk info -e "$1" >/dev/null 2>&1 ;;
  esac
}

pkg_remove() {
  local pkg
  for pkg in "$@"; do
    pkg_is_installed "$pkg" || continue
    case "$PKG_MANAGER" in
      pacman) $SUDO pacman -Rns --noconfirm "$pkg" ;;
      apt)    $SUDO apt-get remove -y "$pkg" ;;
      dnf)    $SUDO dnf remove -y "$pkg" ;;
      zypper) $SUDO zypper --non-interactive remove "$pkg" ;;
      apk)    $SUDO apk del "$pkg" ;;
    esac || warn "Could not remove '$pkg'."
  done
}

### Best-effort per-distro package name tables ##############################

# Runtime Fcitx5 stack: core + Qt/GTK frontends + config GUI + a Bangla-
# capable font.
declare -A FCITX5_RUNTIME_PKGS=(
  [pacman]="fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool noto-fonts"
  [apt]="fcitx5 fcitx5-frontend-gtk3 fcitx5-frontend-qt5 fcitx5-config-qt fonts-noto-core"
  [dnf]="fcitx5 fcitx5-gtk3 fcitx5-qt fcitx5-configtool google-noto-sans-bengali-fonts"
  [zypper]="fcitx5 fcitx5-gtk3 fcitx5-qt5 fcitx5-configtool noto-sans-bengali-fonts"
  [apk]="fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool font-noto"
)

# Build dependencies to compile OpenBangla's Fcitx5 engine from source (only
# used outside the Arch/AUR fast path): a C++ toolchain, CMake, Rust/Cargo
# (for the Riti engine), Qt5 dev headers, and Fcitx5 dev headers.
declare -A OPENBANGLA_BUILD_DEP_PKGS=(
  [pacman]="cmake rust cargo extra-cmake-modules qt5-base base-devel"
  [apt]="cmake rustc cargo extra-cmake-modules qtbase5-dev build-essential pkg-config libfcitx5core-dev libfcitx5config-dev libfcitx5utils-dev"
  [dnf]="cmake rust cargo extra-cmake-modules qt5-qtbase-devel gcc-c++ make fcitx5-devel"
  [zypper]="cmake rust cargo extra-cmake-modules libqt5-qtbase-devel gcc-c++ make fcitx5-devel"
  [apk]="cmake rust cargo extra-cmake-modules qt5-qtbase-dev build-base fcitx5-dev"
)

# IBus/OpenBangla packages that would conflict with this setup, if present.
declare -A CONFLICTING_PKGS=(
  [pacman]="ibus ibus-avro ibus-avro-git ibus-openbangla ibus-openbangla-git openbangla-keyboard openbangla-keyboard-bin openbangla-keyboard-git fcitx5-openbangla-git"
  [apt]="ibus ibus-avro openbangla-keyboard"
  [dnf]="ibus ibus-avro openbangla-keyboard"
  [zypper]="ibus ibus-avro openbangla-keyboard"
  [apk]="ibus openbangla-keyboard"
)

### Generic file helpers #####################################################

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

# Removes a previously-appended managed block (idempotent re-runs), for
# either Lua ("-- BEGIN/END ...") or shell ("# BEGIN/END ...") comment style.
remove_managed_block() {
  local file="$1" begin="$2" end="$3" temporary
  [[ -f "$file" ]] || return 0
  temporary="$(mktemp)"
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { managed=1; next }
    $0 == end { managed=0; next }
    !managed { print }
  ' "$file" > "$temporary"
  install -m 0644 "$temporary" "$file"
  rm -f -- "$temporary"
}

audit() {
  log "Pre-change audit"
  if [[ -r /etc/os-release ]]; then
    printf 'Distro: '; ( . /etc/os-release && printf '%s\n' "${PRETTY_NAME:-unknown}" )
  fi
  printf 'Package manager: %s\n' "$PKG_MANAGER"
  if command -v omarchy >/dev/null 2>&1; then printf 'Omarchy: '; omarchy version 2>&1 || true; fi
  printf 'Kernel: '; uname -r
  printf 'Session: %s / %s\n' "${XDG_CURRENT_DESKTOP:-unknown}" "${XDG_SESSION_TYPE:-unknown}"

  printf '\nInstalled input-method packages:\n'
  case "$PKG_MANAGER" in
    pacman) pacman -Q 2>/dev/null | awk 'BEGIN{IGNORECASE=1} $1 ~ /^(fcitx|ibus|openbangla|avro)/ {print}' ;;
    apt)    dpkg -l 2>/dev/null | awk 'BEGIN{IGNORECASE=1} $2 ~ /^(fcitx|ibus|openbangla|avro)/ {print $2, $3}' ;;
    dnf|zypper) rpm -qa 2>/dev/null | grep -iE '^(fcitx|ibus|openbangla|avro)' ;;
    apk)    apk info 2>/dev/null | grep -iE '^(fcitx|ibus|openbangla|avro)' ;;
  esac || true

  printf '\nInput-method processes:\n'
  ps -eo pid,comm,args | awk '$2 ~ /^(fcitx5|ibus-daemon|openbangla)/ {print}' || true

  printf '\nRelevant environment:\n'
  env | sort | awk -F= '$1 ~ /^(GTK_IM_MODULE|QT_IM_MODULE|QT_IM_MODULES|XMODIFIERS|INPUT_METHOD|SDL_IM_MODULE|GLFW_IM_MODULE|ELECTRON_OZONE_PLATFORM_HINT)$/ {print}' || true

  if command -v rg >/dev/null 2>&1; then
    printf '\nExisting input-method references:\n'
    rg -n -i 'fcitx|ibus|openbangla|GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS' \
      "$HOME/.config/hypr" "$HOME/.config/fcitx5" "$HOME/.config/environment.d" \
      "$HOME/.profile" "$HOME/.xprofile" "$HOME/.zprofile" "$HOME/.pam_environment" \
      2>/dev/null || true
  fi
}

audit

if [[ "${1:-}" == "--audit" ]]; then
  exit 0
elif (($#)); then
  die "Usage: $SCRIPT_NAME [--audit]"
fi

log "Installing the Fcitx5 frontend stack ($PKG_MANAGER)"
log "(If any install below fails with 'not found', refresh your package manager's cache first -- e.g. sudo apt-get update / sudo dnf makecache / sudo zypper refresh -- and re-run.)"
# shellcheck disable=SC2086
pkg_install ${FCITX5_RUNTIME_PKGS[$PKG_MANAGER]}

log "Removing conflicting IBus/OpenBangla packages, if present"
# shellcheck disable=SC2086
pkg_remove ${CONFLICTING_PKGS[$PKG_MANAGER]}

USE_AUR_FASTPATH=false
if [[ "$PKG_MANAGER" == "pacman" ]] && command -v omarchy >/dev/null 2>&1 && command -v yay >/dev/null 2>&1; then
  USE_AUR_FASTPATH=true
fi

if $USE_AUR_FASTPATH; then
  log "Installing OpenBangla's native Fcitx5 engine (AUR fast path)"
  omarchy pkg aur add openbangla-keyboard-fcitx-git
else
  log "Building OpenBangla's native Fcitx5 engine from source"
  if ! { command -v rustc >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1 && command -v cmake >/dev/null 2>&1; }; then
    log "Installing build dependencies ($PKG_MANAGER)"
    # shellcheck disable=SC2086
    pkg_install ${OPENBANGLA_BUILD_DEP_PKGS[$PKG_MANAGER]}
  fi

  build_root="$(mktemp -d)"
  trap 'rm -rf "$build_root"' EXIT

  log "Cloning https://github.com/OpenBangla/OpenBangla-keyboard (develop branch)"
  git clone --recursive --depth 1 --branch develop \
    https://github.com/OpenBangla/OpenBangla-keyboard.git "$build_root/openbangla"

  log "Building the Riti (Rust) input engine"
  (
    cd "$build_root/openbangla/src/engine/riti"
    rust_target="$(rustc -vV | sed -n 's/^host: //p')"
    cargo build --release --target "$rust_target"
    rm -rf release
    cp -r "target/$rust_target/release" ./release
  )

  # CMake's own Rust integration isn't needed since Riti is already built
  # above (mirrors the AUR package's approach).
  sed -i '0,/enable_language(Rust)/{s/^\(\s*\)enable_language(Rust)/\1# enable_language(Rust)/}' \
    "$build_root/openbangla/CMakeLists.txt"

  log "Configuring and building with CMake"
  mkdir -p "$build_root/openbangla/build"
  (
    cd "$build_root/openbangla/build"
    # Install prefix matches the distro's own Fcitx5 (/usr), so the addon
    # ends up in the same lib/fcitx5 directory Fcitx5 already searches.
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
      -DENABLE_FCITX=ON -DENABLE_IBUS=OFF
    rm -rf src/engine/riti
    mkdir -p src/engine
    cp -r "$build_root/openbangla/src/engine/riti" src/engine/
    make -j"$(nproc)"
  )

  log "Installing OpenBangla (requires $SUDO)"
  $SUDO make -C "$build_root/openbangla/build" install
fi

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
  "$HOME/.profile"
  "$HOME/.xprofile"
  "$HOME/.config/chromium-flags.conf"
  "$HOME/.config/brave-flags.conf"
  "$HOME/.config/brave-origin-beta-flags.conf"
  "$HOME/.config/chrome-flags.conf"
  "$HOME/.config/code-flags.conf"
  "$HOME/.config/electron-flags.conf"
  "$HOME/.config/autostart/fcitx5.desktop"
  "$HOME/.config/autostart/org.fcitx.Fcitx5.desktop"
  "$HOME/.config/ibus"
)
for file in "${files_to_change[@]}"; do backup_file "$file"; done
printf 'Backups: %s\n' "$BACKUP_ROOT"

HAS_SYSTEMD=false
[[ -d /run/systemd/system ]] && HAS_SYSTEMD=true

log "Disabling IBus state and autostart conflicts"
if $HAS_SYSTEMD; then
  while read -r unit _; do
    [[ -n "$unit" ]] || continue
    systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
  done < <(systemctl --user list-unit-files --no-legend 2>/dev/null | awk 'tolower($1) ~ /ibus/ {print}')
  # A previous run of an older version of this script used an Omarchy-
  # specific systemd unit; the autostart entry below replaces it.
  systemctl --user list-unit-files --no-legend 2>/dev/null | grep -q '^omarchy-fcitx5\.service' \
    && systemctl --user disable --now omarchy-fcitx5.service >/dev/null 2>&1 || true
fi
pkill -x ibus-daemon 2>/dev/null || true
rm -f "$HOME/.config/autostart/"ibus*.desktop 2>/dev/null || true

# The stale bus files can advertise obsolete IBus addresses. Keep them in the
# timestamped backup, then move the live directory aside instead of deleting it.
if [[ -d "$HOME/.config/ibus" ]]; then
  mv -- "$HOME/.config/ibus" "$HOME/.config/ibus.disabled.$TIMESTAMP"
fi

log "Registering Fcitx5 to start automatically (XDG autostart)"
# Plain XDG autostart works everywhere: systemd turns it into a supervised
# transient unit (xdg-desktop-autostart), and GNOME/KDE/XFCE/most session
# managers process it directly even without systemd.
rm -f "$HOME/.config/autostart/org.fcitx.Fcitx5.desktop"
write_file "$HOME/.config/autostart/fcitx5.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Fcitx5
Comment=Input method framework, providing OpenBangla/Avro Phonetic Bangla input
Exec=fcitx5 --disable notificationitem
Icon=fcitx
Terminal=false
Categories=System;Utility;
X-GNOME-Autostart-enabled=true
EOF

# F12/hotkey trigger keys are cleared below; the toggle is driven externally
# (Hyprland binding or your own DE shortcut running `fcitx5-remote -t`).
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

# The English/OpenBangla input method group itself is configured further
# down, once Fcitx5 is actually running (see "Configuring the input method
# group" below): Fcitx5 owns ~/.config/fcitx5/profile as live daemon state,
# and a hand-written profile that repopulates the group gets silently
# discarded and rewritten back to a bare "keyboard-us"-only default the next
# time Fcitx5 starts. The group must be configured through Fcitx5's own
# org.fcitx.Fcitx.Controller1 D-Bus interface (the same one fcitx5-configtool
# uses), which is what actually persists.

log "Configuring login environment for Wayland, XWayland, Qt, SDL, and kitty"
env_vars=(
  "INPUT_METHOD=fcitx"
  "QT_IM_MODULE=fcitx"
  "XMODIFIERS=@im=fcitx"
  "SDL_IM_MODULE=fcitx"
  "GLFW_IM_MODULE=ibus"
)
if $HAS_SYSTEMD; then
  # GTK_IM_MODULE is intentionally left unset (not set to an empty value):
  # systemd's environment.d parser (systemd 261+) rejects a bare `KEY=` with
  # no right-hand side as invalid syntax and drops the whole line, so an
  # explicit empty assignment silently accomplishes nothing anyway. Leaving
  # it unset lets native GTK3/4 use Wayland text-input-v3; gtk-3.0/gtk-4.0
  # settings below still select Fcitx for X11/XWayland.
  {
    for v in "${env_vars[@]}"; do printf '%s\n' "$v"; done
    printf '%s\n' '# kitty'"'"'s X11 IME frontend speaks the IBus protocol; Fcitx5 provides that'
    printf '%s\n' '# protocol itself. This does not start or require ibus-daemon.'
  } | write_file "$HOME/.config/environment.d/90-openbangla-fcitx5.conf"
  systemctl --user daemon-reload 2>/dev/null || true
else
  # No systemd user manager to process environment.d: fall back to shell
  # profile files, which display managers and X11 sessions read at login.
  for profile_file in "$HOME/.profile" "$HOME/.xprofile"; do
    remove_managed_block "$profile_file" "$MANAGED_BEGIN_SH" "$MANAGED_END_SH"
    {
      printf '\n%s\n' "$MANAGED_BEGIN_SH"
      for v in "${env_vars[@]}"; do printf 'export %s\n' "$v"; done
      printf '%s\n' "$MANAGED_END_SH"
    } >> "$profile_file"
  done
fi

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

HAS_OMARCHY_HYPR=false
if command -v omarchy >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1 && [[ -d "$HOME/.config/hypr" ]]; then
  HAS_OMARCHY_HYPR=true
fi

if $HAS_OMARCHY_HYPR; then
  log "Binding CTRL + SPACE globally (Omarchy/Hyprland)"
  bindings_file="$HOME/.config/hypr/bindings.lua"
  mkdir -p "${bindings_file%/*}"
  touch "$bindings_file"
  remove_managed_block "$bindings_file" "$MANAGED_BEGIN_LUA" "$MANAGED_END_LUA"
  {
    printf '\n%s\n' "$MANAGED_BEGIN_LUA"
    printf '%s\n' '-- CTRL + SPACE is not bound by Omarchy'"'"'s defaults (only SUPER+SPACE and'
    printf '%s\n' '-- other SUPER-combos are). Keep the explicit unbind so a future Omarchy'
    printf '%s\n' '-- default cannot shadow this global toggle.'
    printf '%s\n' 'hl.unbind("CTRL + SPACE")'
    printf '%s\n' 'o.bind("CTRL + SPACE", "Toggle English/Bangla input", "fcitx5-remote -t")'
    printf '%s\n' "$MANAGED_END_LUA"
  } >> "$bindings_file"

  log "Reloading and validating Hyprland"
  hyprctl reload
  config_errors="$(hyprctl configerrors 2>&1 || true)"
  printf '%s\n' "$config_errors"
  if [[ -n "${config_errors//[[:space:]]/}" && "$config_errors" != *"no errors"* ]]; then
    die "Hyprland reported configuration errors. Restore from $BACKUP_ROOT before logging out."
  fi
else
  log "No Omarchy/Hyprland setup detected -- bind the toggle yourself"
  cat <<'EOF'
This script only wires up a global CTRL+SPACE toggle automatically on
Omarchy/Hyprland. On your desktop, bind this command to a key yourself:

    fcitx5-remote -t

Quick examples:

  GNOME (Settings -> Keyboard -> custom shortcuts, or via gsettings):
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
      "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'Toggle Bangla input'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'fcitx5-remote -t'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Control>space'

  KDE Plasma: System Settings -> Shortcuts -> Custom Shortcuts -> new
  command action, command "fcitx5-remote -t", key Ctrl+Space.

  sway/i3: add to your config:
    bindsym Control+space exec fcitx5-remote -t
EOF
fi

log "Starting Fcitx5 and waiting for it on D-Bus"
pkill -x fcitx5 2>/dev/null || true
sleep 0.3
setsid -f fcitx5 --disable notificationitem >/dev/null 2>&1 &
disown

fcitx_running=false
for _ in $(seq 1 20); do
  owner="$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.NameHasOwner org.fcitx.Fcitx5 2>/dev/null || true)"
  [[ "$owner" == "(true,)" ]] && { fcitx_running=true; break; }
  sleep 0.5
done
$fcitx_running || die "Fcitx5 did not start (no org.fcitx.Fcitx5 D-Bus name appeared)."

log "Verifying the OpenBangla install"
if $USE_AUR_FASTPATH; then
  pkg_is_installed openbangla-keyboard-fcitx-git || die "Required package missing: openbangla-keyboard-fcitx-git"
fi
addon_found=false
for lib in /usr/lib/fcitx5/openbangla.so /usr/lib64/fcitx5/openbangla.so \
  /usr/local/lib/fcitx5/openbangla.so /usr/local/lib64/fcitx5/openbangla.so; do
  [[ -f "$lib" ]] && { addon_found=true; break; }
done
$addon_found || die "OpenBangla's Fcitx5 addon library was not found after install."

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

# shellcheck disable=SC2086
for pkg in ${CONFLICTING_PKGS[$PKG_MANAGER]}; do
  pkg_is_installed "$pkg" && die "A conflicting package is still installed: $pkg"
done
pgrep -x ibus-daemon >/dev/null 2>&1 && die "ibus-daemon is still running."

printf '\nSetup complete.\n'
printf 'Backups: %s\n' "$BACKUP_ROOT"
if $HAS_OMARCHY_HYPR; then
  printf 'Final state: English (Ctrl+Space switches to OpenBangla/Avro; Ctrl+Space switches back).\n'
else
  printf 'Final state: English (run `fcitx5-remote -t` to switch to OpenBangla/Avro, or bind it to a key -- see instructions above).\n'
fi
printf 'Log out and back in once so every already-running application inherits the corrected environment.\n'
printf 'After login, fully restart your browser, editors, and terminals before testing.\n'
