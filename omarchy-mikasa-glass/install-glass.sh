#!/usr/bin/env bash
set -euo pipefail

THEME_DIR="$HOME/.config/omarchy/themes/mikasa-glass"
LOOKNFEEL="$HOME/.config/hypr/looknfeel.conf"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$LOOKNFEEL.mikasa-glass-backup-$STAMP"

[[ -f "$THEME_DIR/colors.toml" ]] || { echo "Mikasa Glass theme not found: $THEME_DIR" >&2; exit 1; }
[[ -f "$THEME_DIR/shell.toml" ]] || { echo "Missing shell.toml; re-copy the theme folder." >&2; exit 1; }
[[ -f "$LOOKNFEEL" ]] || { echo "Hyprland config not found: $LOOKNFEEL" >&2; exit 1; }

cp -a "$LOOKNFEEL" "$BACKUP"
export LOOKNFEEL
python - <<'PYCODE'
import os, re, pathlib, sys
p = pathlib.Path(os.environ['LOOKNFEEL'])
s = p.read_text()
s, n = re.subn(r'(?m)^(\s*rounding\s*=\s*)\d+\s*$', r'\g<1>12', s, count=1)
if n != 1:
    print('Could not safely locate rounding setting; config was not modified.', file=sys.stderr)
    sys.exit(2)
m = re.search(r'(?ms)^decoration\s*\{\s*(.*?)^\}', s)
if not m:
    print('Could not locate decoration block; config was not modified.', file=sys.stderr)
    sys.exit(2)
body = m.group(1)
if not re.search(r'(?m)^\s*blur\s*\{', body):
    additions = """
    # Mikasa Glass: balanced blur, moderate GPU cost
    blur {
        enabled = true
        size = 6
        passes = 2
        vibrancy = 0.12
        xray = false
    }

    shadow {
        enabled = true
        range = 10
        render_power = 2
        color = rgba(111,145,190,0.20)
    }
"""
    s = s[:m.start(1)] + body.rstrip() + '\n' + additions + s[m.end(1):]
p.write_text(s)
PYCODE

omarchy theme set mikasa-glass
hyprctl reload
# Avoid `omarchy bar background glass`: this subcommand is unsupported on this Omarchy build.
if command -v omarchy-restart-shell >/dev/null 2>&1; then
  omarchy-restart-shell || true
fi

echo
echo "Mikasa Glass palette applied; Hyprland reloaded."
echo "Backup: $BACKUP"
echo "Shell transparency depends on the installed Omarchy/Quickshell version."
echo "Rollback: cp -a '$BACKUP' '$LOOKNFEEL' && hyprctl reload"
