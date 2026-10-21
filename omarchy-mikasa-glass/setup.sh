#!/usr/bin/env bash
#
# One-command installer for the Mikasa Glass Omarchy theme.
#
#   curl -fsSL https://raw.githubusercontent.com/Abdullah-5603/arch-bash-scripts/master/omarchy-mikasa-glass/setup.sh | bash
#
# Downloads the theme from GitHub, installs it into ~/.config/omarchy/themes,
# copies the wallpapers into the picker folder, and applies the theme.
# Run it from a clone instead and it uses the local files without downloading.
set -euo pipefail

REPO="Abdullah-5603/arch-bash-scripts"
BRANCH="master"
SUBDIR="omarchy-mikasa-glass"
NAME="mikasa-glass"

THEME_DIR="$HOME/.config/omarchy/themes/$NAME"
BG_DIR="$HOME/.config/omarchy/backgrounds/$NAME"

command -v omarchy-theme-set >/dev/null 2>&1 || { echo "omarchy-theme-set not found; this needs Omarchy." >&2; exit 1; }

src=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "$(dirname "${BASH_SOURCE[0]}")/colors.toml" ]]; then
  src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "Downloading theme from github.com/$REPO ..."
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" \
    | tar -xz -C "$tmp" --strip-components=2 "${REPO#*/}-$BRANCH/$SUBDIR"
  src="$tmp"
fi

mkdir -p "$THEME_DIR" "$BG_DIR"
rm -rf "$THEME_DIR/backgrounds"
cp -a "$src/." "$THEME_DIR/"
rm -f "$THEME_DIR/setup.sh"

rm -f "$BG_DIR"/*
cp -a "$src/backgrounds/." "$BG_DIR/"
rm -rf "$HOME/.cache/omarchy/image-selector"

omarchy-theme-set "$NAME"
command -v omarchy-theme-bg-next >/dev/null 2>&1 && omarchy-theme-bg-next || true

echo
echo "Mikasa Glass installed and applied."
echo "Optional: bash $THEME_DIR/install-glass.sh   (adds blur/rounding to ~/.config/hypr/looknfeel.conf)"
