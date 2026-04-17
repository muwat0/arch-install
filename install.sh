#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="${SCRIPT_DIR}/packages.txt"
DOTFILES_REPO_HTTPS="https://git.muwat.org/murat/dotfiles.git"
DOTFILES_REPO_SSH="gitea@git.muwat.org:murat/dotfiles.git"
DOTFILES_DIR="${HOME}/dotfiles"
FONT_DIR="${HOME}/.local/share/fonts"

FIRA_ITALIC_URL="https://github.com/polirritmico/firacode-custom/raw/refs/heads/main/FiraCodeNerdFont-Italic.ttf"
FIRA_BOLDITALIC_URL="https://github.com/polirritmico/firacode-custom/raw/refs/heads/main/FiraCodeNerdFont-BoldItalic.ttf"

COLOR_BOLD="\033[1m"
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"

log() {
	printf "%b%s%b\n" "${COLOR_BOLD}" "$1" "${COLOR_RESET}"
}

warn() {
	printf "%b%s%b\n" "${COLOR_YELLOW}" "$1" "${COLOR_RESET}"
}

error() {
	printf "%b%s%b\n" "${COLOR_RED}" "$1" "${COLOR_RESET}" 1>&2
}

require_file() {
	if [[ ! -f "$1" ]]; then
		error "Missing required file: $1"
		exit 1
	fi
}

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		error "Missing required command: $1"
		exit 1
	fi
}

confirm() {
	local prompt="$1"
	local default_yes="$2"
	local reply

	if [[ "$default_yes" == "true" ]]; then
		read -r -p "${prompt} [Y/n]: " reply
		[[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]
	else
		read -r -p "${prompt} [y/N]: " reply
		[[ "$reply" =~ ^[Yy]$ ]]
	fi
}

check_internet() {
	if ! ping -c 1 -W 2 archlinux.org >/dev/null 2>&1; then
		error "No internet connectivity detected."
		exit 1
	fi
}

ensure_yay() {
	if command -v yay >/dev/null 2>&1; then
		return
	fi

	log "Installing yay..."
	require_cmd git
	require_cmd sudo

	sudo pacman -Sy --needed --noconfirm base-devel

	local temp_dir
	temp_dir="$(mktemp -d)"
	git clone https://aur.archlinux.org/yay.git "${temp_dir}/yay"
	pushd "${temp_dir}/yay" >/dev/null
	makepkg -si --noconfirm
	popd >/dev/null
	rm -rf "${temp_dir}"
}

clone_dotfiles() {
	if [[ -d "${DOTFILES_DIR}/.git" ]]; then
		log "Dotfiles already cloned at ${DOTFILES_DIR}."
		return
	fi

	log "Cloning dotfiles repo..."
	if git clone --depth 1 "${DOTFILES_REPO_SSH}" "${DOTFILES_DIR}"; then
		return
	fi

	warn "SSH clone failed. Retrying with HTTPS..."
	if git clone --depth 1 "${DOTFILES_REPO_HTTPS}" "${DOTFILES_DIR}"; then
		return
	fi

	warn "HTTPS clone failed. Retrying with HTTP/1.1 and no tags..."
	if git -c http.version=HTTP/1.1 clone --depth 1 --no-tags "${DOTFILES_REPO_HTTPS}" "${DOTFILES_DIR}"; then
		return
	fi

	error "Failed to clone dotfiles repo. Check credentials, SSH keys, or network stability."
	exit 1
}

select_menu_single() {
	local title="$1"
	local default="$2"
	shift 2
	local options=("$@")
	local choice

	log "$title"
	select choice in "${options[@]}"; do
		if [[ -n "${choice:-}" ]]; then
			echo "$choice"
			return
		fi
		warn "Invalid selection."
	done <<<"$default"
}

select_menu_multi() {
	local title="$1"
	shift 1
	local options=("$@")
	local choices=()
	local input

	log "$title"
	local i=1
	for option in "${options[@]}"; do
		echo "  [$i] $option"
		i=$((i + 1))
	done
	echo "  [0] Done"

	while true; do
		read -r -p "Select option number (0 to finish): " input
		if [[ "$input" == "0" ]]; then
			break
		fi
		if [[ "$input" =~ ^[0-9]+$ ]] && ((input >= 1 && input <= ${#options[@]})); then
			local selected="${options[$((input - 1))]}"
			if [[ " ${choices[*]} " == *" ${selected} "* ]]; then
				warn "Already selected: ${selected}"
			else
				choices+=("${selected}")
			fi
		else
			warn "Invalid selection."
		fi
	done

	echo "${choices[@]}"
}

has_nvidia() {
	lspci | grep -i nvidia >/dev/null 2>&1
}

read_packages_by_group() {
	local group_pattern="$1"
	awk -v pattern="$group_pattern" '
    BEGIN {in_group=0}
    /^# === / {in_group=0}
    $0 ~ pattern {in_group=1; next}
    in_group && $0 !~ /^#/ && NF {print $0}
  ' "${PACKAGES_FILE}"
}

read_all_packages() {
	awk '
    $0 !~ /^#/ && NF {print $0}
  ' "${PACKAGES_FILE}"
}

install_packages() {
	local packages=("$@")
	if [[ ${#packages[@]} -eq 0 ]]; then
		warn "No packages to install."
		return
	fi

	log "Installing packages..."
	yay -S --needed --noconfirm "${packages[@]}"
}

install_fonts() {
	log "Installing custom FiraCode italic variants..."
	mkdir -p "${FONT_DIR}"

	local temp_dir
	temp_dir="$(mktemp -d)"
	if ! wget -q -O "${temp_dir}/FiraCodeNerdFont-Italic.ttf" "${FIRA_ITALIC_URL}"; then
		warn "Failed to download FiraCode italic font."
	fi
	if ! wget -q -O "${temp_dir}/FiraCodeNerdFont-BoldItalic.ttf" "${FIRA_BOLDITALIC_URL}"; then
		warn "Failed to download FiraCode bold italic font."
	fi

	if ls "${temp_dir}"/*.ttf >/dev/null 2>&1; then
		mv -f "${temp_dir}"/*.ttf "${FONT_DIR}/"
		fc-cache -f >/dev/null 2>&1 || warn "Failed to refresh font cache."
	fi
	rm -rf "${temp_dir}"
}

stow_configs() {
	local stow_dirs=("$@")
	if [[ ${#stow_dirs[@]} -eq 0 ]]; then
		warn "No configs selected for stow."
		return
	fi

	log "Applying dotfiles with stow..."
	for dir in "${stow_dirs[@]}"; do
		if [[ -d "${DOTFILES_DIR}/${dir}" ]]; then
			stow -d "${DOTFILES_DIR}" -t "${HOME}" "${dir}" || warn "Stow failed for ${dir}"
		else
			warn "Missing dotfiles directory: ${dir}"
		fi
	done
}

enable_services() {
	log "Enabling services..."
	sudo systemctl enable --now NetworkManager.service || warn "Failed to enable NetworkManager"
	sudo systemctl enable --now bluetooth.service || warn "Failed to enable Bluetooth"
	sudo systemctl enable --now docker.service || warn "Failed to enable Docker"

	if systemctl list-unit-files | grep -q "tlp.service"; then
		sudo systemctl enable --now tlp.service || warn "Failed to enable TLP"
	fi

	if systemctl list-unit-files | grep -q "libvirtd.service"; then
		sudo systemctl enable --now libvirtd.service || warn "Failed to enable libvirtd"
	fi

	if systemctl list-unit-files | grep -q "plasmalogin.service"; then
		sudo systemctl enable --now plasmalogin.service || warn "Failed to enable plasmalogin"
	fi
}

enable_timers() {
	log "Enabling maintenance timers..."
	local timers=(
		fstrim.timer
		paccache.timer
		reflector.timer
		archlinux-keyring-wkd-sync.timer
		man-db.timer
		plocate-updatedb.timer
		shadow.timer
	)
	for timer in "${timers[@]}"; do
		if systemctl list-unit-files | grep -q "^${timer}"; then
			sudo systemctl enable --now "${timer}" || warn "Failed to enable ${timer}"
		fi
	done
}

main() {
	require_file "${PACKAGES_FILE}"
	require_cmd sudo
	require_cmd awk
	require_cmd ping
	require_cmd wget
	require_cmd fc-cache
	require_cmd lspci

	if [[ "$(id -u)" -eq 0 ]]; then
		error "Do not run this script as root."
		exit 1
	fi

	check_internet
	ensure_yay
	clone_dotfiles

	local wm_selection
	local terminal_choice
	local shell_choice
	local editor_choice
	local install_ollama

	wm_selection=($(select_menu_multi "Select WM/DE (multi-select)" "plasma" "hyprland"))
	terminal_choice="$(select_menu_single "Select terminal" "ghostty" "ghostty" "kitty" "alacritty")"
	shell_choice="$(select_menu_single "Select shell" "bash" "bash" "zsh")"
	editor_choice="$(select_menu_single "Select editor" "nvim" "nvim" "vim" "emacs")"
	install_ollama=false
	if confirm "Install Ollama?" false; then
		install_ollama=true
	fi

	local packages=()

	packages+=($(read_packages_by_group "# === CORE ==="))
	packages+=($(read_packages_by_group "# === CLI ESSENTIALS ==="))
	packages+=($(read_packages_by_group "# === CONTAINERS ==="))
	packages+=($(read_packages_by_group "# === FONTS ==="))
	packages+=($(read_packages_by_group "# === SHARED DESKTOP/TOOLS ==="))
	packages+=($(read_packages_by_group "# === CONNECTIVITY ==="))
	packages+=($(read_packages_by_group "# === POWER/LAPTOP ==="))
	packages+=($(read_packages_by_group "# === VPN ==="))
	packages+=($(read_packages_by_group "# === VIRTUALIZATION ==="))
	packages+=($(read_packages_by_group "# === BROWSERS ==="))
	packages+=($(read_packages_by_group "# === MESSAGING/SOCIAL ==="))
	packages+=($(read_packages_by_group "# === PRODUCTIVITY ==="))
	packages+=($(read_packages_by_group "# === MEDIA/NETWORK ==="))
	packages+=($(read_packages_by_group "# === GAMING/DEV ==="))
	packages+=($(read_packages_by_group "# === RECORDING ==="))

	if [[ " ${wm_selection[*]} " == *" plasma "* ]]; then
		packages+=(plasma plasma-login-manager)
	fi
	if [[ " ${wm_selection[*]} " == *" hyprland "* ]]; then
		packages+=(hyprland waybar swaync hypridle hyprlock hyprpaper)
	fi

	case "$terminal_choice" in
	ghostty)
		packages+=(ghostty ghostty-shell-integration ghostty-terminfo)
		;;
	kitty)
		packages+=(kitty)
		;;
	alacritty)
		packages+=(alacritty)
		;;
	esac

	case "$shell_choice" in
	bash)
		packages+=(bash)
		;;
	zsh)
		packages+=(zsh)
		;;
	esac

	case "$editor_choice" in
	nvim)
		packages+=(neovim)
		;;
	vim)
		packages+=(vim)
		;;
	emacs)
		packages+=(emacs)
		;;
	esac

	if has_nvidia; then
		if confirm "NVIDIA GPU detected. Install NVIDIA packages?" true; then
			packages+=(nvidia nvidia-utils nvidia-settings nvidia-prime nvidia-open)
		fi
	else
		if confirm "No NVIDIA GPU detected. Install NVIDIA packages anyway?" false; then
			packages+=(nvidia nvidia-utils nvidia-settings nvidia-prime nvidia-open)
		fi
	fi

	if [[ "$install_ollama" == "true" ]]; then
		if has_nvidia; then
			packages+=(ollama-cuda)
		else
			packages+=(ollama)
		fi
	fi

	log "Package selection complete."
	if confirm "Proceed with installation?" true; then
		install_packages "${packages[@]}"
	else
		warn "Installation canceled."
		exit 0
	fi

	install_fonts

	local stow_dirs=("bash" "fastfetch" "mpv" "nvim" "rofi" "starship" "tmux" "waybar" "zsh" "kitty" "alacritty" "ghostty" "hyprland" "hypridle" "hyprlock" "hyprpaper" "emacs" "vim")
	local selected_stow=()

	for dir in "${stow_dirs[@]}"; do
		case "$dir" in
		kitty | alacritty | ghostty)
			if [[ "$terminal_choice" == "$dir" ]]; then
				selected_stow+=("$dir")
			fi
			;;
		bash | zsh)
			if [[ "$shell_choice" == "$dir" ]]; then
				selected_stow+=("$dir")
			fi
			;;
		nvim | vim | emacs)
			if [[ "$editor_choice" == "$dir" ]]; then
				selected_stow+=("$dir")
			fi
			;;
		hyprland | hypridle | hyprlock | hyprpaper | waybar)
			if [[ " ${wm_selection[*]} " == *" hyprland "* ]]; then
				selected_stow+=("$dir")
			fi
			;;
		*)
			selected_stow+=("$dir")
			;;
		esac
	done

	stow_configs "${selected_stow[@]}"
	enable_services
	enable_timers

	log "Done. Your system should be ready to use."
}

main "$@"
