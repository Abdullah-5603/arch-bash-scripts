# Anime Glass Theme for Omarchy 4

A balanced frosted-glass theme for Omarchy 4 / Quickshell, using a fixed cyan, lavender, rose, and midnight palette.

## Included
- `colors.toml` — coordinated terminal and shell palette
- `shell.toml` — translucent Omarchy Quickshell bar, menus, popups, launcher, notifications, OSD surfaces, polkit prompt, lock screen, and image picker tokens
- `install-glass.sh` — backs up and updates the user's Hyprland look-and-feel config, applies the theme, attempts to restart the shell
- `setup.sh` — one-command installer (see below)
- Ten anime wallpapers in `backgrounds/`

## Quick install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/Abdullah-5603/arch-bash-scripts/master/omarchy-anime-glass/setup.sh | bash
```

Downloads the theme, installs it to `~/.config/omarchy/themes/anime-glass`, copies the wallpapers into the picker folder and applies the theme.

## Manual install

Copy the extracted theme directory into the user theme folder:

```bash
mkdir -p ~/.config/omarchy/themes/anime-glass
cp -a ~/Downloads/omarchy-anime-glass-theme/. ~/.config/omarchy/themes/anime-glass/
```

Then run:

```bash
bash ~/.config/omarchy/themes/anime-glass/install-glass.sh
```

The installer checks for the theme files, backs up `~/.config/hypr/looknfeel.conf`, sets the existing window rounding to 12, adds moderate blur and shadows if a blur block is not already present, applies the theme, reloads Hyprland and attempts to restart the shell if the helper is installed. It avoids the unsupported `omarchy bar background` command. It does not replace `shell.json`, so your existing bar layout and widgets are preserved.

## Rollback

The installer prints the exact backup path. Restore it with:

```bash
cp -a ~/.config/hypr/looknfeel.conf.anime-glass-backup-TIMESTAMP ~/.config/hypr/looknfeel.conf
hyprctl reload
```

Replace `TIMESTAMP` with the actual suffix printed by the installer. To return the bar to opaque mode, run `omarchy bar background opaque`. To return to another theme, use `omarchy theme set THEME_NAME`.

## Notes

- `shell.toml` controls Omarchy shell surface colors and alpha values; transparency appearance depends on the shell implementation and compositor.
- `~/.config/omarchy/shell.toml`, if present, is a machine-wide override and takes precedence over theme values for matching keys. Back it up/remove only if you intentionally want to stop overriding the theme.
- Hyprland blur uses GPU resources. If performance suffers, restore the printed backup and/or reduce blur size/passes.
- Wallpapers are individual 1920×1080 (16:9) JPEGs. The woman appears in one modest, non-sexualized pink outfit scene; the remaining wallpapers are scenery/city/workspace images.


## Wallpaper update

The three included wallpapers are landscape-only anime scenery: sakura lake at sunset, rainy neon Tokyo, and a moonlit shrine. They contain no sexualized characters.
