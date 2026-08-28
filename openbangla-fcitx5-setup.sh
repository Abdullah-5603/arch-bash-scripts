#!/usr/bin/env bash
#
# Configure OpenBangla Keyboard's Fcitx5 engine for Bangla (Avro Phonetic)
# input, on any Linux distribution and desktop environment/window manager.
#
# - Arch Linux with Omarchy + yay: uses the AUR package (fast path).
# - Everything else (Debian/Ubuntu, Fedora/RHEL, openSUSE, Alpine, or plain
#   Arch without yay/Omarchy): builds OpenBangla's Fcitx5 engine from source
#   (git clone + cmake; the Riti Rust engine is built by the project's own
#   corrosion-rs integration). This path needs network access and a C++/Rust
#   toolchain.
#
# Non-Arch package names below are a best-effort mapping across distro
# families -- if a specific one has changed on your distro/version, package
# installs are attempted one at a time with a warning (not a hard failure),
# and the actual build step further down will fail with a concrete, fixable
# error (e.g. a missing header) if something important is really absent.
#
# Cooperating with a system that already manages Fcitx5:
# - If a systemd user unit already owns Fcitx5 (Omarchy ships
#   omarchy-fcitx5.service, and masks the fcitx5 package's XDG autostart
#   entry with a Hidden=true override so the unit is the only starter), this
#   script leaves that unit in charge and restarts it. It does not install a
#   competing autostart entry, and it does not hand-start a second fcitx5.
# - Where no such unit exists, Fcitx5 autostart uses a plain XDG
#   ~/.config/autostart/*.desktop entry (works under systemd's
#   xdg-desktop-autostart integration, GNOME, KDE, XFCE, and most session
#   managers).
# - Login environment variables are written only for the ones the system does
#   not already provide in /usr/lib/environment.d, /etc/environment.d, or
#   /usr/local/lib/environment.d. They go through systemd's environment.d
#   when systemd is present, and through ~/.profile / ~/.xprofile otherwise.
# - The global CTRL+SPACE toggle is wired up automatically on Hyprland (Lua
#   or conf bindings, whichever your setup uses); everywhere else this script
#   prints the command (`fcitx5-remote -t`) and example steps to bind it
#   yourself.
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
readonly DISABLED_MARKER="disabled by $SCRIPT_NAME on $TIMESTAMP"

# Where the system itself can set login environment variables. /etc/environment
# deserves special mention: systemd ships
# /usr/lib/environment.d/99-environment.conf as a symlink to it, so its
# contents land at priority 99 -- above every other drop-in here -- and
# pam_env reads it for tty and ssh logins too. An IM variable parked there
# overrides everything else this script does.
readonly SYSTEM_ENV_DIRS=(
  /usr/lib/environment.d
  /usr/local/lib/environment.d
  /run/environment.d
  /etc/environment.d
)

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

# Asks whether a package is installed *under that name*, not whether
# something satisfies it. The distinction matters here: `pacman -Q
# openbangla-keyboard` succeeds once openbangla-keyboard-fcitx-git is
# installed, because that package carries provides=('openbangla-keyboard') --
# so a naive check reports the engine this script just installed as a
# conflicting leftover, and would also make a re-run remove it. Match the
# resolved name against the one asked about. dpkg -s and rpm -q are already
# name-exact (provides need --whatprovides), so they are left alone.
pkg_is_installed() {
  case "$PKG_MANAGER" in
    pacman) pacman -Qq "$1" 2>/dev/null | grep -qxF "$1" ;;
    apt)    dpkg -s "$1" >/dev/null 2>&1 ;;
    dnf)    rpm -q "$1" >/dev/null 2>&1 ;;
    zypper) rpm -q "$1" >/dev/null 2>&1 ;;
    apk)    apk info -e "$1" 2>/dev/null | grep -qxF "$1" ;;
  esac
}

# Removing an input-method framework has to take its engine packages with it:
# ibus-m17n (and friends) depend on ibus, so a plain removal is refused by the
# package manager and the conflict silently survives. pacman needs -c to
# cascade; apt/dnf/zypper/apk cascade by default.
pkg_remove() {
  local pkg cascade
  for pkg in "$@"; do
    pkg_is_installed "$pkg" || continue
    case "$PKG_MANAGER" in
      pacman)
        cascade="$($SUDO pacman -Rnsc --print --print-format '%n' "$pkg" 2>/dev/null | tr '\n' ' ' || true)"
        if [[ -n "${cascade// /}" ]]; then
          printf 'Removing (with dependants): %s\n' "$cascade"
        fi
        $SUDO pacman -Rnsc --noconfirm "$pkg"
        ;;
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

# OpenBangla's own hard dependencies, needed on BOTH paths.
#
# Qt5 Svg is the important one: OpenBangla's top-level CMakeLists.txt does
#   find_package(Qt5 COMPONENTS Widgets Network Svg REQUIRED)
# but neither AUR PKGBUILD (openbangla-keyboard-fcitx-git,
# openbangla-keyboard-git) lists it, so on a machine without it the AUR build
# dies at configure time with "Could not find a package configuration file
# provided by Qt5Svg" -- which is why the AUR fast path needs it installed up
# front rather than left to the PKGBUILD. libzstd is likewise required by
# pkg_check_modules(ZSTD REQUIRED libzstd).
declare -A OPENBANGLA_DEP_PKGS=(
  [pacman]="qt5-svg zstd"
  [apt]="libqt5svg5-dev libzstd-dev"
  [dnf]="qt5-qtsvg-devel libzstd-devel"
  [zypper]="libqt5-qtsvg-devel libzstd-devel"
  [apk]="qt5-qtsvg-dev zstd-dev"
)

# Build dependencies to compile OpenBangla's Fcitx5 engine from source (only
# used outside the Arch/AUR fast path): a C++ toolchain, CMake, Rust/Cargo
# (the project's bundled corrosion-rs drives cargo itself), Qt5 dev headers,
# and Fcitx5 dev headers.
declare -A OPENBANGLA_BUILD_DEP_PKGS=(
  [pacman]="cmake rust cargo extra-cmake-modules qt5-base base-devel"
  [apt]="cmake rustc cargo extra-cmake-modules qtbase5-dev build-essential pkg-config libfcitx5core-dev libfcitx5config-dev libfcitx5utils-dev"
  [dnf]="cmake rust cargo extra-cmake-modules qt5-qtbase-devel gcc-c++ make fcitx5-devel"
  [zypper]="cmake rust cargo extra-cmake-modules libqt5-qtbase-devel gcc-c++ make fcitx5-devel"
  [apk]="cmake rust cargo extra-cmake-modules qt5-qtbase-dev build-base fcitx5-dev"
)

# IBus/OpenBangla packages that would conflict with this setup, if present.
# Removal cascades to dependants (see pkg_remove), so listing "ibus" also
# takes out ibus-m17n and any other ibus engine.
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

# Comments matching lines out in place rather than deleting them, so the
# change stays visible and hand-reversible (a full copy is in the timestamped
# backup as well). `cat >` rather than `install` keeps the file's own mode --
# these are the user's own rc files, not files this script owns.
comment_out_matching() {
  local file="$1" prefix="$2" pattern="$3" privileged="${4:-false}" temporary
  [[ -f "$file" ]] || return 0
  grep -qE "$pattern" "$file" 2>/dev/null || return 0
  printf 'Disabling in %s:\n' "${file/#$HOME/\~}"
  grep -nE "$pattern" "$file" | sed 's/^/    /'
  temporary="$(mktemp)"
  awk -v prefix="$prefix" -v marker="$DISABLED_MARKER" -v pattern="$pattern" '
    $0 ~ pattern { print prefix " " $0 "  " prefix " " marker; next }
    { print }
  ' "$file" > "$temporary"
  if [[ "$privileged" == "true" ]]; then
    # cp onto the existing file keeps its owner and mode.
    $SUDO cp -- "$temporary" "$file"
  else
    cat "$temporary" > "$file"
  fi
  rm -f -- "$temporary"
}

# True when the system already exports this variable with exactly the value
# wanted, from a drop-in it ships itself (Omarchy's
# /usr/lib/environment.d/10-omarchy-fcitx.conf, for example).
#
# Matching the value, not just the name, is the whole point: a leftover that
# sets QT_IM_MODULE=ibus would otherwise read as "already provided" and this
# script would politely defer to it -- writing nothing, and leaving the
# session pointed at an input method that is no longer installed.
env_var_provided_systemwide() {
  local name="$1" value="$2" directory
  for directory in "${SYSTEM_ENV_DIRS[@]}"; do
    [[ -d "$directory" ]] || continue
    if grep -rqxF "$name=$value" "$directory" 2>/dev/null; then
      return 0
    fi
  done
  if [[ -f /etc/environment ]] && grep -qxF "$name=$value" /etc/environment 2>/dev/null; then
    return 0
  fi
  return 1
}

### Session / service detection #############################################

HAS_SYSTEMD=false
if [[ -d /run/systemd/system ]]; then
  HAS_SYSTEMD=true
fi

# A systemd user unit that already owns fcitx5, if the distro ships one.
# Omarchy has omarchy-fcitx5.service (enabled, WantedBy graphical-session);
# some distros ship fcitx5.service instead. When one exists it -- not this
# script -- is what starts and supervises fcitx5.
detect_fcitx_service() {
  local unit
  $HAS_SYSTEMD || return 0
  for unit in omarchy-fcitx5.service fcitx5.service org.fcitx.Fcitx5.service; do
    if systemctl --user list-unit-files "$unit" --no-legend 2>/dev/null | grep -q .; then
      printf '%s' "$unit"
      return 0
    fi
  done
  return 0
}
FCITX_SERVICE="$(detect_fcitx_service)"
readonly FCITX_SERVICE

fcitx_stop() {
  if [[ -n "$FCITX_SERVICE" ]]; then
    systemctl --user stop "$FCITX_SERVICE" >/dev/null 2>&1 || true
  fi
  # Also catch a hand-started instance from an earlier run of this script.
  pkill -x fcitx5 >/dev/null 2>&1 || true
  sleep 0.5
}

fcitx_start() {
  if [[ -n "$FCITX_SERVICE" ]]; then
    systemctl --user restart "$FCITX_SERVICE"
  else
    setsid -f fcitx5 --disable notificationitem >/dev/null 2>&1 || true
  fi
}

### Audit ####################################################################

audit() {
  log "Pre-change audit"
  if [[ -r /etc/os-release ]]; then
    printf 'Distro: '; ( . /etc/os-release && printf '%s\n' "${PRETTY_NAME:-unknown}" )
  fi
  printf 'Package manager: %s\n' "$PKG_MANAGER"
  if command -v omarchy >/dev/null 2>&1; then printf 'Omarchy: '; omarchy version 2>&1 || true; fi
  printf 'Kernel: '; uname -r
  printf 'Session: %s / %s\n' "${XDG_CURRENT_DESKTOP:-unknown}" "${XDG_SESSION_TYPE:-unknown}"
  printf 'Fcitx5 systemd user unit: %s\n' "${FCITX_SERVICE:-none (this script will install an XDG autostart entry)}"

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

### Packages #################################################################

log "Installing the Fcitx5 frontend stack ($PKG_MANAGER)"
log "(If any install below fails with 'not found', refresh your package manager's cache first -- e.g. sudo apt-get update / sudo dnf makecache / sudo zypper refresh -- and re-run.)"
# shellcheck disable=SC2086
pkg_install ${FCITX5_RUNTIME_PKGS[$PKG_MANAGER]}

log "Installing OpenBangla's build/runtime dependencies that its packaging omits"
# shellcheck disable=SC2086
pkg_install ${OPENBANGLA_DEP_PKGS[$PKG_MANAGER]}

log "Removing conflicting IBus/OpenBangla packages, if present"
# shellcheck disable=SC2086
pkg_remove ${CONFLICTING_PKGS[$PKG_MANAGER]}

USE_AUR_FASTPATH=false
if [[ "$PKG_MANAGER" == "pacman" ]] && command -v yay >/dev/null 2>&1; then
  USE_AUR_FASTPATH=true
fi

if $USE_AUR_FASTPATH; then
  log "Installing OpenBangla's native Fcitx5 engine (AUR fast path)"
  if command -v omarchy >/dev/null 2>&1; then
    omarchy pkg aur add openbangla-keyboard-fcitx-git
  else
    yay -S --noconfirm --needed openbangla-keyboard-fcitx-git
  fi
else
  log "Building OpenBangla's native Fcitx5 engine from source"
  if ! { command -v rustc >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1 && command -v cmake >/dev/null 2>&1; }; then
    log "Installing build dependencies ($PKG_MANAGER)"
    # shellcheck disable=SC2086
    pkg_install ${OPENBANGLA_BUILD_DEP_PKGS[$PKG_MANAGER]}
  fi

  build_root="$(mktemp -d)"
  trap 'rm -rf "$build_root"' EXIT

  # --recursive matters: the tree carries both the Riti engine and
  # cmake/corrosion-rs as submodules, and the build needs both.
  log "Cloning https://github.com/OpenBangla/OpenBangla-keyboard (develop branch)"
  git clone --recursive --depth 1 --branch develop \
    https://github.com/OpenBangla/OpenBangla-keyboard.git "$build_root/openbangla"

  # Riti is NOT pre-built by hand here. Upstream used to require
  # enable_language(Rust) plus a manual `cargo build` copied into the build
  # tree; develop now drives cargo through its bundled corrosion-rs from
  # add_subdirectory(cmake/corrosion-rs), so cmake builds the Rust engine
  # itself and the old patch-and-copy dance no longer applies.
  log "Configuring and building with CMake (corrosion-rs builds the Riti engine)"
  cmake -S "$build_root/openbangla" -B "$build_root/openbangla/build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
    -DENABLE_FCITX=ON -DENABLE_IBUS=OFF
  cmake --build "$build_root/openbangla/build" -j"$(nproc)"

  log "Installing OpenBangla (requires $SUDO)"
  $SUDO cmake --install "$build_root/openbangla/build"
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

### Backups ##################################################################

### Legacy IBus leftovers to sweep up #######################################

# An earlier IBus/Avro attempt leaves three kinds of debris behind, each of
# which quietly defeats Fcitx5 even after ibus itself is uninstalled:
#   - GTK_IM_MODULE/QT_IM_MODULE/XMODIFIERS=ibus exports in shell rc files and
#     in the session environment. On Omarchy, ~/.config/uwsm/env.d is the one
#     that really hurts: uwsm feeds it to the entire graphical session, so it
#     outranks the distro's own /usr/lib/environment.d fcitx defaults and
#     every app comes up asking for an IBus that is no longer there.
#   - an `exec-once = ibus-daemon ...` line in the compositor config.
#   - a hand-rolled ibus toggle script bound to a key.
# Gather the files here so the backup below covers them before anything moves.
collect_files() {
  local found
  while IFS= read -r found; do
    if [[ -n "$found" ]]; then printf '%s\n' "$found"; fi
  done < <("$@" 2>/dev/null | sort)
}

ibus_env_files=(
  "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc"
  "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc"
  "$HOME/.xprofile" "$HOME/.pam_environment"
  "$HOME/.config/uwsm/env" "$HOME/.config/uwsm/env-hyprland"
)
while IFS= read -r found_file; do
  ibus_env_files+=("$found_file")
done < <(collect_files find "$HOME/.config/uwsm/env.d" -maxdepth 1 -type f ! -name '*.bak')
while IFS= read -r found_file; do
  ibus_env_files+=("$found_file")
done < <(collect_files find "$HOME/.config/environment.d" -maxdepth 1 -type f -name '*.conf')

ibus_conf_files=()
while IFS= read -r found_file; do
  ibus_conf_files+=("$found_file")
done < <(collect_files find "$HOME/.config/hypr" -maxdepth 1 -type f -name '*.conf')

ibus_lua_files=()
while IFS= read -r found_file; do
  ibus_lua_files+=("$found_file")
done < <(collect_files find "$HOME/.config/hypr" -maxdepth 1 -type f -name '*.lua')

log "Creating timestamped backups before editing user configuration"
files_to_change=(
  "${ibus_env_files[@]}"
  "${ibus_conf_files[@]}"
  "${ibus_lua_files[@]}"
  "$HOME/.local/bin/avro-toggle"
  "/etc/environment"
  "$HOME/.config/fcitx5/config"
  "$HOME/.config/fcitx5/profile"
  "$HOME/.config/environment.d/90-openbangla-fcitx5.conf"
  "$HOME/.config/gtk-3.0/settings.ini"
  "$HOME/.config/gtk-4.0/settings.ini"
  "$HOME/.config/hypr/bindings.lua"
  "$HOME/.config/hypr/bindings.conf"
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

### IBus teardown ############################################################

log "Disabling IBus state and autostart conflicts"
if $HAS_SYSTEMD; then
  while read -r unit _; do
    [[ -n "$unit" ]] || continue
    systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
  done < <(systemctl --user list-unit-files --no-legend 2>/dev/null | awk 'tolower($1) ~ /ibus/ {print}')
fi
pkill -x ibus-daemon >/dev/null 2>&1 || true
rm -f "$HOME/.config/autostart/"ibus*.desktop 2>/dev/null || true

log "Disabling leftover IBus environment and autostart from earlier attempts"
# GLFW_IM_MODULE is deliberately absent from this list: kitty's X11 IME
# frontend speaks the IBus protocol, Fcitx5 implements that protocol, and the
# environment section below sets GLFW_IM_MODULE=ibus on purpose.
readonly IBUS_ENV_PATTERN='^[[:space:]]*(export[[:space:]]+)?(GTK_IM_MODULE|QT_IM_MODULE|QT_IM_MODULES|XMODIFIERS|INPUT_METHOD|SDL_IM_MODULE)[[:space:]]*=.*ibus'
readonly IBUS_ALIAS_PATTERN='^[[:space:]]*alias[[:space:]]+ibus'
readonly IBUS_SESSION_PATTERN='^[[:space:]]*(exec-once|exec|bind|bindd)[[:space:]]*=.*(ibus|avro-toggle)'
readonly IBUS_LUA_PATTERN='^[[:space:]]*[^-].*(ibus-daemon|ibus start|avro-toggle)'

for file in "${ibus_env_files[@]}"; do
  comment_out_matching "$file" "#" "$IBUS_ENV_PATTERN"
  comment_out_matching "$file" "#" "$IBUS_ALIAS_PATTERN"
done
for file in "${ibus_conf_files[@]}"; do
  comment_out_matching "$file" "#" "$IBUS_SESSION_PATTERN"
done
for file in "${ibus_lua_files[@]}"; do
  comment_out_matching "$file" "--" "$IBUS_LUA_PATTERN"
done

# /etc/environment outranks every drop-in (see SYSTEM_ENV_DIRS) and is read by
# pam_env for non-graphical logins, so a stale IM variable there survives
# everything above. It is root-owned, hence the privileged sweep.
comment_out_matching "/etc/environment" "#" "$IBUS_ENV_PATTERN" true
for file in "${SYSTEM_ENV_DIRS[@]}"; do
  while IFS= read -r found_file; do
    # Skip the /etc/environment symlink, already handled above.
    if [[ ! -L "$found_file" ]]; then
      comment_out_matching "$found_file" "#" "$IBUS_ENV_PATTERN" true
    fi
  done < <(collect_files find "$file" -maxdepth 1 -name '*.conf')
done

# An IBus-era toggle script is dead weight once ibus is gone, and its key
# binding has just been commented out above.
if [[ -f "$HOME/.local/bin/avro-toggle" ]]; then
  mv -- "$HOME/.local/bin/avro-toggle" "$HOME/.local/bin/avro-toggle.disabled.$TIMESTAMP"
  printf 'Moved aside: ~/.local/bin/avro-toggle (IBus-based, superseded by `fcitx5-remote -t`)\n'
fi

# The stale bus files can advertise obsolete IBus addresses. Keep them in the
# timestamped backup, then move the live directory aside instead of deleting it.
if [[ -d "$HOME/.config/ibus" ]]; then
  mv -- "$HOME/.config/ibus" "$HOME/.config/ibus.disabled.$TIMESTAMP"
fi

### Fcitx5 startup ###########################################################

# Everything below rewrites ~/.config/fcitx5/*, which is live daemon state:
# fcitx5 flushes its in-memory copy over those files when it shuts down, so a
# still-running instance would overwrite whatever is written here the moment
# it is restarted. Stop it first, write, then start it again.
fcitx_stop

if [[ -n "$FCITX_SERVICE" ]]; then
  log "Fcitx5 startup is owned by the systemd user unit '$FCITX_SERVICE' -- leaving it in charge"
  systemctl --user enable "$FCITX_SERVICE" >/dev/null 2>&1 || true
  # A distro that supervises fcitx5 with a unit also masks the fcitx5
  # package's /etc/xdg/autostart entry with a Hidden=true override, so the
  # two starters cannot race. Restore that override if an earlier run of this
  # script removed it, and drop the competing entry older versions installed.
  rm -f "$HOME/.config/autostart/fcitx5.desktop"
  if [[ -f /etc/xdg/autostart/org.fcitx.Fcitx5.desktop \
     && ! -f "$HOME/.config/autostart/org.fcitx.Fcitx5.desktop" ]]; then
    write_file "$HOME/.config/autostart/org.fcitx.Fcitx5.desktop" <<'EOF'
[Desktop Entry]
Hidden=true
EOF
  fi
else
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
fi

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

### Login environment ########################################################

log "Configuring login environment for Wayland, XWayland, Qt, SDL, and kitty"
env_vars=(
  "INPUT_METHOD=fcitx"
  "QT_IM_MODULE=fcitx"
  "XMODIFIERS=@im=fcitx"
  "SDL_IM_MODULE=fcitx"
  "GLFW_IM_MODULE=ibus"
)

# Only add what the system does not already export itself.
missing_env_vars=()
for v in "${env_vars[@]}"; do
  name="${v%%=*}"
  if env_var_provided_systemwide "$name" "${v#*=}"; then
    printf 'Already provided system-wide: %s\n' "$name"
  else
    missing_env_vars+=("$v")
  fi
done

if $HAS_SYSTEMD; then
  # GTK_IM_MODULE is intentionally left unset (not set to an empty value):
  # systemd's environment.d parser (systemd 261+) rejects a bare `KEY=` with
  # no right-hand side as invalid syntax and drops the whole line, so an
  # explicit empty assignment silently accomplishes nothing anyway. Leaving
  # it unset lets native GTK3/4 use Wayland text-input-v3; gtk-3.0/gtk-4.0
  # settings below still select Fcitx for X11/XWayland.
  if ((${#missing_env_vars[@]})); then
    {
      for v in "${missing_env_vars[@]}"; do printf '%s\n' "$v"; done
      printf '%s\n' '# kitty'"'"'s X11 IME frontend speaks the IBus protocol; Fcitx5 provides that'
      printf '%s\n' '# protocol itself. This does not start or require ibus-daemon.'
    } | write_file "$HOME/.config/environment.d/90-openbangla-fcitx5.conf"
  else
    printf 'Every variable is already provided system-wide; no drop-in needed.\n'
    rm -f "$HOME/.config/environment.d/90-openbangla-fcitx5.conf"
  fi
  systemctl --user daemon-reload 2>/dev/null || true
else
  # No systemd user manager to process environment.d: fall back to shell
  # profile files, which display managers and X11 sessions read at login.
  for profile_file in "$HOME/.profile" "$HOME/.xprofile"; do
    remove_managed_block "$profile_file" "$MANAGED_BEGIN_SH" "$MANAGED_END_SH"
    if ((${#missing_env_vars[@]})); then
      {
        printf '\n%s\n' "$MANAGED_BEGIN_SH"
        for v in "${missing_env_vars[@]}"; do printf 'export %s\n' "$v"; done
        printf '%s\n' "$MANAGED_END_SH"
      } >> "$profile_file"
    fi
  done
fi

# Writing the files above only fixes the *next* login. The running session
# still holds whatever it imported at login, which is why a setup that is
# correct on disk can still look completely broken until a logout.
if $HAS_SYSTEMD; then
  log "Refreshing the running session's environment"
  session_env=("${env_vars[@]}")
  # GTK_IM_MODULE stays unset for future logins (native Wayland
  # text-input-v3 beats the immodule), but a value the user manager inherited
  # from pam_env -- /etc/environment is read at login, before this script gets
  # to clean it -- cannot be removed now: `unset-environment` exits 0 and
  # changes nothing. Where one is stuck, aim it at fcitx so GTK applications
  # launched in this session load the fcitx5-gtk immodule instead of hunting
  # for an ibus that is no longer installed.
  systemctl --user unset-environment GTK_IM_MODULE >/dev/null 2>&1 || true
  if systemctl --user show-environment 2>/dev/null | grep -q '^GTK_IM_MODULE='; then
    session_env+=("GTK_IM_MODULE=fcitx")
  fi
  for v in "${session_env[@]}"; do
    systemctl --user set-environment "$v" >/dev/null 2>&1 || true
  done
  # Pass explicit NAME=VALUE. Given bare names this tool copies values out of
  # *this* process's environment -- which still carries the stale ibus ones,
  # inherited the same way -- and would faithfully republish exactly what was
  # just cleaned up, silently undoing the set-environment calls above.
  if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd "${session_env[@]}" >/dev/null 2>&1 || true
  fi
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

### CTRL + SPACE toggle ######################################################

HYPR_BINDING_STYLE="none"
if command -v hyprctl >/dev/null 2>&1 && [[ -d "$HOME/.config/hypr" ]]; then
  if [[ -f "$HOME/.config/hypr/bindings.lua" ]]; then
    HYPR_BINDING_STYLE="lua"
  elif [[ -f "$HOME/.config/hypr/bindings.conf" ]]; then
    HYPR_BINDING_STYLE="conf"
  fi
fi

case "$HYPR_BINDING_STYLE" in
  lua)
    log "Binding CTRL + SPACE globally (Hyprland, Lua bindings)"
    bindings_file="$HOME/.config/hypr/bindings.lua"
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
    ;;
  conf)
    log "Binding CTRL + SPACE globally (Hyprland, conf bindings)"
    bindings_file="$HOME/.config/hypr/bindings.conf"
    remove_managed_block "$bindings_file" "$MANAGED_BEGIN_SH" "$MANAGED_END_SH"
    {
      printf '\n%s\n' "$MANAGED_BEGIN_SH"
      printf '%s\n' 'unbind = CTRL, SPACE'
      printf '%s\n' 'bind = CTRL, SPACE, exec, fcitx5-remote -t'
      printf '%s\n' "$MANAGED_END_SH"
    } >> "$bindings_file"
    ;;
esac

if [[ "$HYPR_BINDING_STYLE" != "none" ]]; then
  log "Reloading and validating Hyprland"
  hyprctl reload
  config_errors="$(hyprctl configerrors 2>&1 || true)"
  printf '%s\n' "$config_errors"
  if [[ -n "${config_errors//[[:space:]]/}" && "$config_errors" != *"no errors"* ]]; then
    die "Hyprland reported configuration errors. Restore from $BACKUP_ROOT before logging out."
  fi
else
  log "No Hyprland setup detected -- bind the toggle yourself"
  cat <<'EOF'
This script only wires up a global CTRL+SPACE toggle automatically on
Hyprland. On your desktop, bind this command to a key yourself:

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

### Start Fcitx5 and configure the input method group ########################

log "Starting Fcitx5 and waiting for it on D-Bus"
fcitx_start

fcitx_running=false
for _ in $(seq 1 20); do
  owner="$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.NameHasOwner org.fcitx.Fcitx5 2>/dev/null || true)"
  if [[ "$owner" == "(true,)" ]]; then
    fcitx_running=true
    break
  fi
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
  if [[ -f "$lib" ]]; then
    addon_found=true
    break
  fi
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

### Final conflict re-check ##################################################

# `pkg_is_installed x && die ...` looks equivalent but is not: under `set -e`
# the whole AND-list is the tested command, so a package that is absent makes
# the list return non-zero and kills the script right before it reports
# success. Same reason every other `test && action` above is an `if`.
# shellcheck disable=SC2086
for pkg in ${CONFLICTING_PKGS[$PKG_MANAGER]}; do
  if pkg_is_installed "$pkg"; then
    die "A conflicting package is still installed: $pkg"
  fi
done
if pgrep -x ibus-daemon >/dev/null 2>&1; then
  die "ibus-daemon is still running."
fi

leftover_system_env="$(grep -rnE '^[[:space:]]*(GTK_IM_MODULE|QT_IM_MODULE|QT_IM_MODULES|XMODIFIERS|INPUT_METHOD|SDL_IM_MODULE)=.*ibus' \
  /etc/environment "${SYSTEM_ENV_DIRS[@]}" 2>/dev/null || true)"
if [[ -n "$leftover_system_env" ]]; then
  warn "A system file still points an input-method variable at ibus; it will override this setup at next login:"
  printf '%s\n' "$leftover_system_env" >&2
fi

printf '\nSetup complete.\n'
printf 'Backups: %s\n' "$BACKUP_ROOT"
if [[ "$HYPR_BINDING_STYLE" != "none" ]]; then
  printf 'Final state: English (Ctrl+Space switches to OpenBangla/Avro; Ctrl+Space switches back).\n'
else
  printf 'Final state: English (run `fcitx5-remote -t` to switch to OpenBangla/Avro, or bind it to a key -- see instructions above).\n'
fi
printf 'Log out and back in once so every already-running application inherits the corrected environment.\n'
printf 'After login, fully restart your browser, editors, and terminals before testing.\n'
