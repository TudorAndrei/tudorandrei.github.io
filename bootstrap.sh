#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/TudorAndrei/dotfiles.git}"
SSH_URL="${DOTFILES_SSH_REPO:-git@github.com:TudorAndrei/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
SSH_KEY="${DOTFILES_SSH_KEY:-$HOME/.ssh/github}"
SKIP_AUTH="${DOTFILES_SKIP_AUTH:-0}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

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

ensure_mise() {
    local mise
    mise="$(command -v mise || echo "$HOME/.local/bin/mise")"
    if [ ! -x "$mise" ]; then
        log "Installing mise..."
        curl -fsSL https://mise.run | sh >/dev/null 2>&1 || return 1
        mise="$HOME/.local/bin/mise"
    fi
    [ -x "$mise" ] || return 1
    echo "$mise"
}

gh_cmd() {
    local mise
    if command -v gh >/dev/null 2>&1; then
        echo "gh"
        return 0
    fi
    if mise="$(ensure_mise)"; then
        echo "$mise x gh@latest -- gh"
        return 0
    fi
    if pkg_install gh github-cli gh gh >/dev/null 2>&1; then
        echo "gh"
        return 0
    fi
    return 1
}

ensure_ssh_config() {
    local cfg="$HOME/.ssh/config"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    [ -f "$cfg" ] || { touch "$cfg" && chmod 600 "$cfg"; }
    if grep -qiE '^[[:space:]]*Host[[:space:]]+([^#]*[[:space:]])?github\.com([[:space:]]|$)' "$cfg"; then
        return 0
    fi
    log "Adding the github.com entry to ~/.ssh/config..."
    {
        printf '\nHost github.com\n'
        printf '    HostName github.com\n'
        printf '    AddKeysToAgent yes\n'
        printf '    User git\n'
        printf '    PreferredAuthentications publickey\n'
        if [ "$(uname -s)" = "Darwin" ]; then
            printf '    UseKeychain yes\n'
        fi
        printf '    IdentityFile %s\n' "$SSH_KEY"
    } >>"$cfg"
}

ensure_ssh_key() {
    [ -f "$SSH_KEY" ] && return 0
    log "Making an SSH key at $SSH_KEY..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "$(id -un)@$(hostname -s 2>/dev/null || hostname)"
}

is_headless() {
    [ "$(uname -s)" = "Darwin" ] && return 1
    [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && return 1
    return 0
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
        warn "No terminal for the GitHub login. For an SSH setup use:"
        warn "  bash -c \"\$(curl -fsSL https://tudorandrei.github.io/bootstrap.sh)\""
        return 1
    fi
    gh="$(gh_cmd)" || {
        warn "gh is not available; install it and run 'gh auth login' to use SSH"
        return 1
    }
    ensure_ssh_key
    if is_headless; then
        export BROWSER=true
        log "This machine has no browser."
        log "Open https://github.com/login/device on another machine"
        log "and give it the code that gh shows below."
    fi
    log "Starting the GitHub login..."
    $gh auth login --hostname github.com --git-protocol ssh \
        --scopes admin:public_key --skip-ssh-key --web || return 1
    log "Uploading the public key to GitHub..."
    $gh ssh-key add "$SSH_KEY.pub" --title "$(hostname -s 2>/dev/null || hostname)" ||
        warn "The key upload failed; add $SSH_KEY.pub manually"
    for _ in 1 2 3 4 5; do
        github_ssh_works && return 0
        sleep 3
    done
    return 1
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

ensure_ssh_config

if github_ssh_works || github_login; then
    use_ssh_remotes
else
    warn "No GitHub SSH key on this machine; the remotes stay on HTTPS"
    warn "Run 'gh auth login' later, then start this script again"
fi

echo ""
exec bash "$DOTFILES_DIR/scripts/bootstrap.sh"
