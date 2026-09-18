#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/TudorAndrei/dotfiles.git}"
SSH_URL="${DOTFILES_SSH_REPO:-git@github.com:TudorAndrei/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
SKIP_AUTH="${DOTFILES_SKIP_AUTH:-0}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

if [ ! -t 0 ] && [ -r /dev/tty ]; then
    exec </dev/tty
fi

pkg_install() {
    local apt_pkg="$1" pacman_pkg="$2" dnf_pkg="$3" brew_pkg="$4" sudo=""
    [ "$(id -u)" -eq 0 ] || sudo="sudo"
    if command -v brew >/dev/null 2>&1; then
        brew install "$brew_pkg"
    elif command -v apt-get >/dev/null 2>&1; then
        $sudo apt-get update -qq
        $sudo apt-get install -y "$apt_pkg"
    elif command -v pacman >/dev/null 2>&1; then
        $sudo pacman -Sy --noconfirm "$pacman_pkg"
    elif command -v dnf >/dev/null 2>&1; then
        $sudo dnf install -y "$dnf_pkg"
    else
        return 1
    fi
}

ensure_git() {
    command -v git >/dev/null 2>&1 && return 0
    log "Installing git..."
    if [ "$(uname -s)" = "Darwin" ] && ! command -v brew >/dev/null 2>&1; then
        die "git is missing. Run 'xcode-select --install', then start this script again."
    fi
    pkg_install git git git git ||
        die "No known package manager. Install git, then start this script again."
}

gh_cmd() {
    local mise
    if command -v gh >/dev/null 2>&1; then
        echo "gh"
        return 0
    fi
    mise="$(command -v mise || echo "$HOME/.local/bin/mise")"
    if [ -x "$mise" ]; then
        echo "$mise x gh@latest -- gh"
        return 0
    fi
    if pkg_install gh github-cli gh gh >/dev/null 2>&1; then
        echo "gh"
        return 0
    fi
    return 1
}

github_ssh_works() {
    command -v ssh >/dev/null 2>&1 || return 1
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 |
        grep -q 'successfully authenticated'
}

github_login() {
    local gh
    if [ "$SKIP_AUTH" = "1" ]; then
        return 1
    fi
    if [ ! -t 0 ]; then
        warn "No terminal available for the GitHub login; the remotes stay on HTTPS"
        return 1
    fi
    gh="$(gh_cmd)" || {
        warn "gh is not available; install it and run 'gh auth login' to use SSH"
        return 1
    }
    log "Starting the GitHub login (select SSH and let gh upload a key)..."
    $gh auth login --hostname github.com --git-protocol ssh || return 1
    github_ssh_works
}

use_ssh_remotes() {
    local path url
    log "Switching the remotes to SSH..."
    git -C "$DOTFILES_DIR" remote set-url origin "$SSH_URL"
    while read -r path; do
        [ -d "$DOTFILES_DIR/$path/.git" ] || [ -f "$DOTFILES_DIR/$path/.git" ] || continue
        url="$(git -C "$DOTFILES_DIR/$path" remote get-url origin 2>/dev/null || true)"
        [ -n "$url" ] || continue
        git -C "$DOTFILES_DIR/$path" remote set-url origin \
            "${url/https:\/\/github.com\//git@github.com:}"
    done < <(git -C "$DOTFILES_DIR" config -f .gitmodules --get-regexp 'submodule\..*\.path' |
        awk '{ print $2 }')
}

echo "=== Dotfiles Bootstrap ==="
echo ""

ensure_git

if [ -d "$DOTFILES_DIR/.git" ]; then
    log "Updating $DOTFILES_DIR..."
    git -C "$DOTFILES_DIR" pull --ff-only || warn "pull failed; the current checkout stays"
elif [ -e "$DOTFILES_DIR" ]; then
    die "$DOTFILES_DIR exists and is not a git repository"
else
    log "Cloning into $DOTFILES_DIR..."
    git clone --recurse-submodules "$REPO_URL" "$DOTFILES_DIR"
fi

if github_ssh_works || github_login; then
    use_ssh_remotes
else
    warn "No GitHub SSH key on this machine; the remotes stay on HTTPS"
    warn "Run 'gh auth login' later, then start this script again"
fi

echo ""
exec bash "$DOTFILES_DIR/scripts/bootstrap.sh"
