# Arch Install

Interactive post-install setup script for fresh Arch Linux installs. Uses `yay`, applies dotfiles with `stow`, installs your preferred apps, enables services, and finishes system readiness in one run.

## Features
- Installs `yay` if missing
- Multi-select WM/DE: Plasma and/or Hyprland
- Default terminal: Ghostty (selectable)
- Default shell: Bash (selectable)
- Optional Ollama install (CUDA when NVIDIA is present)
- NVIDIA detection with install prompt
- Installs FiraCode Nerd Font plus custom italic variants
- Enables services and maintenance timers

## Requirements
- Arch Linux (post-install, non-root user)
- Internet connection
- `sudo` configured

## Files
- `install.sh`: main installer script
- `packages.txt`: package inventory grouped by category

## Usage
```bash
chmod +x ./install.sh
./install.sh
```

## Notes
- The script clones dotfiles into `~/dotfiles`.
- Dotfile application is selective based on your choices.
- Font variants are downloaded to `~/.local/share/fonts` and cached.
- Services enabled include `NetworkManager`, `bluetooth`, `docker`, plus optional `tlp`, `libvirtd`, and `plasmalogin`.
- Timers enabled include `fstrim`, `paccache`, `reflector`, `archlinux-keyring-wkd-sync`, `man-db`, `plocate-updatedb`, and `shadow` (if present).

## Customize
- Edit `packages.txt` to add/remove packages.
- Update selections or defaults in `install.sh`.

## License
MIT
