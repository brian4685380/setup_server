#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Config
# =========================
ZSH_VERSION="5.9"
NEOVIM_VERSION="0.11.4"
ZOXIDE_VERSION="0.9.8"

INSTALL_ZSH=0
INSTALL_Z4H=0
FORCE_LAZYVIM=0
AUTO_HANDOFF=1

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# =========================
# Helpers
# =========================
say() { printf "\n\033[1m==> %s\033[0m\n" "$*"; }
warn() { printf "\n\033[33m[warn]\033[0m %s\n" "$*" >&2; }
die() {
  printf "\n\033[31m[error]\033[0m %s\n" "$*" >&2
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

TMPDIR_BOOTSTRAP=""
cleanup() {
  [[ -n "${TMPDIR_BOOTSTRAP:-}" && -d "${TMPDIR_BOOTSTRAP:-}" ]] && rm -rf "$TMPDIR_BOOTSTRAP"
}
trap cleanup EXIT
trap 'die "failed at line $LINENO"' ERR

download() {
  local url="$1"
  local out="$2"
  if have curl; then
    curl -fL --retry 3 --retry-delay 1 -o "$out" "$url"
  elif have wget; then
    wget -O "$out" "$url"
  else
    die "Neither curl nor wget is available"
  fi
}

ensure_dir() {
  mkdir -p "$1"
}

ensure_line() {
  local line="$1"
  local file="$2"
  touch "$file"
  grep -qxF "$line" "$file" || echo "$line" >>"$file"
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
  x86_64 | amd64) echo "x86_64" ;;
  aarch64 | arm64) echo "arm64" ;;
  *)
    die "Unsupported architecture: $arch"
    ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --install-zsh) INSTALL_ZSH=1 ;;
    --install-z4h) INSTALL_Z4H=1 ;;
    --force-lazyvim) FORCE_LAZYVIM=1 ;;
    --no-auto-handoff) AUTO_HANDOFF=0 ;;
    -h | --help)
      cat <<'EOF'
Usage: ./bootstrap.sh [options]

Options:
  --install-zsh       Build/install zsh into $HOME
  --install-z4h       Run zsh4humans installer (interactive; runs last)
  --force-lazyvim     Replace existing ~/.config/nvim
  --no-auto-handoff   Do not add bash -> zsh handoff block
  -h, --help          Show this help
EOF
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
    esac
    shift
  done
}

ensure_base_layout() {
  say "Preparing base layout"

  ensure_dir "$HOME/bin"
  ensure_dir "$HOME/apps"
  ensure_dir "$HOME/.config"
  ensure_dir "$HOME/.config/shell"

  export PATH="$HOME/bin:$PATH"

  ensure_line 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc"
  ensure_line 'export PATH="$HOME/bin:$PATH"' "$HOME/.zshrc"

  local zrc="$HOME/.config/shell/bootstrap.zsh"
  touch "$zrc"

  if ! grep -qF 'source "$HOME/.config/shell/bootstrap.zsh"' "$HOME/.zshrc" 2>/dev/null; then
    cat >>"$HOME/.zshrc" <<'EOF'

# User-managed bootstrap
[[ -f "$HOME/.config/shell/bootstrap.zsh" ]] && source "$HOME/.config/shell/bootstrap.zsh"
EOF
  fi
}

install_zsh() {
  [[ "$INSTALL_ZSH" -eq 1 ]] || return 0

  if have zsh; then
    say "zsh already exists at $(command -v zsh); skipping build"
    return 0
  fi

  say "Installing zsh $ZSH_VERSION into \$HOME"

  TMPDIR_BOOTSTRAP="$(mktemp -d)"
  local tarball="$TMPDIR_BOOTSTRAP/zsh.tar.xz"

  download "https://www.zsh.org/pub/zsh-${ZSH_VERSION}.tar.xz" "$tarball"

  tar -xf "$tarball" -C "$TMPDIR_BOOTSTRAP"
  cd "$TMPDIR_BOOTSTRAP/zsh-$ZSH_VERSION"

  ./configure --prefix="$HOME"
  make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  make install

  say "zsh installed at $HOME/bin/zsh"
}

configure_auto_handoff() {
  [[ "$AUTO_HANDOFF" -eq 1 ]] || return 0

  say "Configuring bash -> zsh handoff"

  if ! grep -q 'BEGIN bootstrap-zsh-handoff' "$HOME/.bashrc" 2>/dev/null; then
    cat >>"$HOME/.bashrc" <<'EOF'

# BEGIN bootstrap-zsh-handoff
# Emulate "default shell = zsh" without chsh/sudo.
# Only applies to interactive bash shells.
if [[ $- == *i* ]] && [[ -z "${ZSH_VERSION:-}" ]]; then
  if [[ -x "$HOME/bin/zsh" ]]; then
    exec "$HOME/bin/zsh" -l
  elif command -v zsh >/dev/null 2>&1; then
    exec "$(command -v zsh)" -l
  fi
fi
# END bootstrap-zsh-handoff
EOF
  fi
}

install_z4h() {
  [[ "$INSTALL_Z4H" -eq 1 ]] || return 0

  say "Installing zsh4humans"
  warn "zsh4humans is interactive and may rewrite ~/.zshrc"
  warn "It is intentionally run at the end"

  have zsh || [[ -x "$HOME/bin/zsh" ]] || die "zsh is required before installing zsh4humans"

  if [[ ! -t 0 || ! -t 1 ]]; then
    die "zsh4humans installer needs an interactive terminal"
  fi

  if have curl; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install)"
  else
    sh -c "$(wget -O- https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install)"
  fi
}

install_p10k_config() {
  say "Configuring Powerlevel10k"

  local zrc="$HOME/.config/shell/bootstrap.zsh"

  if [[ -f "$HOME/.p10k.zsh" ]]; then
    say "~/.p10k.zsh already exists; keeping it"
  elif [[ -f "$SCRIPT_DIR/.p10k.zsh" ]]; then
    cp "$SCRIPT_DIR/.p10k.zsh" "$HOME/.p10k.zsh"
    say "Copied $SCRIPT_DIR/.p10k.zsh -> ~/.p10k.zsh"
  else
    warn "No .p10k.zsh found next to the script; skipping copy"
  fi

  ensure_line '[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"' "$zrc"
}

install_neovim() {
  say "Installing Neovim $NEOVIM_VERSION"

  local arch nvim_pkg extract_dir
  arch="$(detect_arch)"

  case "$arch" in
  x86_64)
    nvim_pkg="nvim-linux-x86_64.tar.gz"
    extract_dir="nvim-linux-x86_64"
    ;;
  arm64)
    nvim_pkg="nvim-linux-arm64.tar.gz"
    extract_dir="nvim-linux-arm64"
    ;;
  esac

  local dst="$HOME/apps/$nvim_pkg"
  download "https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/${nvim_pkg}" "$dst"

  rm -rf "$HOME/apps/$extract_dir"
  tar -xzf "$dst" -C "$HOME/apps"

  [[ -x "$HOME/apps/$extract_dir/bin/nvim" ]] || die "nvim binary not found after extraction"
  ln -sf "$HOME/apps/$extract_dir/bin/nvim" "$HOME/bin/nvim"
}

install_zoxide() {
  say "Installing zoxide $ZOXIDE_VERSION"

  local arch zoxide_pkg
  arch="$(detect_arch)"
  case "$arch" in
  x86_64) zoxide_pkg="zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz" ;;
  arm64) zoxide_pkg="zoxide-${ZOXIDE_VERSION}-aarch64-unknown-linux-musl.tar.gz" ;;
  esac

  ensure_dir "$HOME/apps/zoxide"
  local dst="$HOME/apps/zoxide/$zoxide_pkg"
  download "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/${zoxide_pkg}" "$dst"

  rm -rf "$HOME/apps/zoxide/extract"
  mkdir -p "$HOME/apps/zoxide/extract"
  tar -xzf "$dst" -C "$HOME/apps/zoxide/extract"

  local zox
  zox="$(find "$HOME/apps/zoxide/extract" -type f -name zoxide | head -n1 || true)"
  [[ -n "$zox" ]] || die "zoxide binary not found after extraction"

  install -m 0755 "$zox" "$HOME/bin/zoxide"

  local zrc="$HOME/.config/shell/bootstrap.zsh"
  ensure_line 'eval "$(zoxide init zsh)"' "$zrc"
}

install_eza() {
  say "Installing eza"

  local arch eza_pkg
  arch="$(detect_arch)"

  case "$arch" in
  x86_64) eza_pkg="eza_x86_64-unknown-linux-gnu.tar.gz" ;;
  arm64) eza_pkg="eza_aarch64-unknown-linux-gnu.tar.gz" ;;
  esac

  ensure_dir "$HOME/apps/eza"
  local tmpfile="$HOME/apps/eza/$eza_pkg"
  download "https://github.com/eza-community/eza/releases/latest/download/${eza_pkg}" "$tmpfile"

  rm -rf "$HOME/apps/eza/extract"
  mkdir -p "$HOME/apps/eza/extract"
  tar -xzf "$tmpfile" -C "$HOME/apps/eza/extract"

  local ezabin
  ezabin="$(find "$HOME/apps/eza/extract" -type f -name eza | head -n1 || true)"
  [[ -n "$ezabin" ]] || die "eza binary not found after extraction"

  ln -sf "$ezabin" "$HOME/bin/eza"
}

configure_shell() {
  say "Writing shell config"

  local zrc="$HOME/.config/shell/bootstrap.zsh"
  touch "$zrc"

  ensure_line "alias gs='git status'" "$zrc"
  ensure_line "alias ga='git add'" "$zrc"
  ensure_line "alias gc='git commit'" "$zrc"
  ensure_line "alias ls='eza -al --icons=auto'" "$zrc"
  ensure_line "alias ll='eza -l --icons=auto'" "$zrc"
  ensure_line "alias vim='nvim'" "$zrc"
}

install_lazyvim() {
  say "Installing LazyVim starter"

  ensure_dir "$HOME/.config"

  if [[ -d "$HOME/.config/nvim" ]]; then
    if [[ "$FORCE_LAZYVIM" -eq 1 ]]; then
      mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak.$(date +%s)"
    else
      warn "~/.config/nvim already exists; skipping LazyVim install"
      warn "Use --force-lazyvim if you want to replace it"
      return 0
    fi
  fi

  git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
  rm -rf "$HOME/.config/nvim/.git"
}

install_monokai_pro_plugin() {
  say "Installing Monokai Pro plugin override"

  local plugin_dir="$HOME/.config/nvim/lua/plugins"
  ensure_dir "$plugin_dir"

  if [[ -f "$SCRIPT_DIR/monokai-pro.lua" ]]; then
    cp "$SCRIPT_DIR/monokai-pro.lua" "$plugin_dir/monokai-pro.lua"
    say "Copied $SCRIPT_DIR/monokai-pro.lua -> $plugin_dir/monokai-pro.lua"
  else
    warn "No monokai-pro.lua found next to the script; skipping"
  fi
}

main() {
  parse_args "$@"
  ensure_base_layout
  install_zsh
  install_neovim
  install_zoxide
  install_eza
  configure_shell
  install_p10k_config
  install_lazyvim
  install_monokai_pro_plugin
  configure_auto_handoff
  install_z4h

  say "Done."
  echo
  echo "Next steps:"
  echo "  1. Put these files next to the script if you want them copied:"
  echo "     - .p10k.zsh"
  echo "     - monokai-pro.lua"
  echo "  2. Open a new terminal"
  echo "  3. Or run: exec zsh -l"
}

main "$@"
