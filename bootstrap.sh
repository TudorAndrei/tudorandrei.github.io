#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/TudorAndrei/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

if [ ! -t 0 ] && [ -r /dev/tty ]; then
    exec </dev/tty
fi

install_git() {
    case "$(uname -s)" in
        Darwin)
            die "git is missing. Run 'xcode-select --install', then start this script again."
            ;;
        Linux)
            if [ "$(id -u)" -eq 0 ]; then sudo=""; else sudo="sudo"; fi
            if command -v apt-get >/dev/null 2>&1; then
                $sudo apt-get update -qq
                $sudo apt-get install -y git
            elif command -v pacman >/dev/null 2>&1; then
                $sudo pacman -Sy --noconfirm git
            elif command -v dnf >/dev/null 2>&1; then
                $sudo dnf install -y git
            else
                die "No known package manager. Install git, then start this script again."
            fi
            ;;
        *)
            die "Unsupported operating system: $(uname -s)"
            ;;
    esac
}

echo "=== Dotfiles Bootstrap ==="
echo ""

command -v git >/dev/null 2>&1 || install_git

if [ -d "$DOTFILES_DIR/.git" ]; then
    log "Updating $DOTFILES_DIR..."
    git -C "$DOTFILES_DIR" pull --ff-only || log "WARNING: pull failed; the current checkout stays"
elif [ -e "$DOTFILES_DIR" ]; then
    die "$DOTFILES_DIR exists and is not a git repository"
else
    log "Cloning into $DOTFILES_DIR..."
    git clone --recurse-submodules "$REPO_URL" "$DOTFILES_DIR"
fi

echo ""
exec bash "$DOTFILES_DIR/scripts/bootstrap.sh"
