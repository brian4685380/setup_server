#!/usr/bi#!/usr/bin/env bash
set -Eeuo pipefail

# ====== helpers ======
say() { printf "\n\033[1m==> %s\033[0m\n" "$*"; }
warn() { printf "\n\033[33m[warn]\033[0m %s\n" "$*" >&2; }
die() {
  printf "\n\033[31m[error]\033[0m %s\n" "$*" >&2
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ensure_line() {
  local line="$1"
  local file="$2"
  touch "$file"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >>"$file"
}

# Ensure ~/bin exists and is first on PATH (for this run and future shells)
mkdir -p "$HOME/bin"
export PATH="$HOME/bin:$PATH"
ensure_line 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc"
ensure_line 'export PATH="$HOME/bin:$PATH"' "$HOME/.zshrc"

# Make sure login bash shells also load ~/.bashrc (important for SSH)
ensure_bash_login_sources_bashrc() {
  say "Ensuring login bash shells source ~/.bashrc"

  if ! grep -qF '. "$HOME/.bashrc"' "$HOME/.bash_profile" 2>/dev/null; then
    cat >>"$HOME/.bash_profile" <<'EOF'
# Load ~/.bashrc for login shells
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
EOF
  fi

  if ! grep -qF '. "$HOME/.bashrc"' "$HOME/.profile" 2>/dev/null; then
    cat >>"$HOME/.profile" <<'EOF'
# Load ~/.bashrc for login shells
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
EOF
  fi
}

# Emulate "default shell = zsh" without sudo/chsh
configure_bash_to_zsh_handoff() {
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

# ====== 1) (Optional) Install zsh from source into $HOME ======
install_zsh() {
  say "Installing zsh (from source) into \$HOME (optional)"

  # Skip if a zsh is already present in PATH
  if have zsh; then
    say "zsh already available at $(command -v zsh). Skipping build."
    return 0
  fi

  # Need wget/curl, tar, make, a compiler toolchain; we assume they exist
  cd "$HOME"
  rm -rf zsh-src zsh.tar zsh.tar.xz || true
  if have wget; then
    wget -O zsh.tar.xz "https://sourceforge.net/projects/zsh/files/latest/download"
  else
    curl -L -o zsh.tar.xz "https://sourceforge.net/projects/zsh/files/latest/download"
  fi
  mkdir -p zsh-src
  unxz zsh.tar.xz
  tar -xvf zsh.tar -C zsh-src --strip-components 1
  cd zsh-src
  ./configure --prefix="$HOME"
  make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  make install
  cd "$HOME"
  rm -rf zsh-src zsh.tar || true
}

# ====== 2) Install zsh4humans (v5) ======
install_z4h() {
  say "Installing zsh4humans v5"
  warn "zsh4humans installer is interactive and may rewrite ~/.zshrc"

  # Run installer via curl or wget
  if have curl; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install)"
  else
    sh -c "$(wget -O- https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install)"
  fi

  # Ensure PATH still exists afterwards
  ensure_line 'export PATH="$HOME/bin:$PATH"' "$HOME/.zshrc"
}

# ====== 3) Powerlevel10k config ======
install_p10k() {
  say "Configuring Powerlevel10k"

  if [ -f "$HOME/.p10k.zsh" ]; then
    say "~/.p10k.zsh already present. Skipping copy."
  elif [ -f "$SCRIPT_DIR/.p10k.zsh" ]; then
    cp "$SCRIPT_DIR/.p10k.zsh" "$HOME/.p10k.zsh"
  else
    say "No .p10k.zsh found next to the script; skipping."
  fi

  if ! grep -q '\.p10k\.zsh' "$HOME/.zshrc" 2>/dev/null; then
    cat >>"$HOME/.zshrc" <<'EOF'
# Load Powerlevel10k config if present
[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
EOF
  fi
}

# ====== 4) Install Neovim to ~/apps and symlink to ~/bin ======
install_neovim() {
  say "Installing Neovim v0.11.4 (linux64)"
  mkdir -p "$HOME/apps" && cd "$HOME/apps"
  local NVPKG="nvim-linux-x86_64.tar.gz"
  rm -f "$NVPKG"
  if have curl; then
    curl -fL -o "$NVPKG" "https://github.com/neovim/neovim/releases/download/v0.11.4/nvim-linux-x86_64.tar.gz"
  else
    wget -O "$NVPKG" "https://github.com/neovim/neovim/releases/download/v0.11.4/nvim-linux-x86_64.tar.gz"
  fi
  rm -rf "$HOME/apps/nvim-linux-x86_64"
  tar xzf "$NVPKG"
  ln -sf "$HOME/apps/nvim-linux-x86_64/bin/nvim" "$HOME/bin/nvim"
}

# ====== 5) Install zoxide (musl static) ======
install_zoxide() {
  say "Installing zoxide v0.9.8 (musl)"
  mkdir -p "$HOME/apps/zoxide" && cd "$HOME/apps/zoxide"
  local ZO="zoxide-0.9.8-x86_64-unknown-linux-musl.tar.gz"
  rm -f "$ZO"
  if have curl; then
    curl -fL -o "$ZO" "https://github.com/ajeetdsouza/zoxide/releases/download/v0.9.8/${ZO}"
  else
    wget -O "$ZO" "https://github.com/ajeetdsouza/zoxide/releases/download/v0.9.8/${ZO}"
  fi
  rm -rf "$HOME/apps/zoxide/extract" || true
  mkdir -p "$HOME/apps/zoxide/extract"
  tar -xzf "$ZO" -C "$HOME/apps/zoxide/extract"

  local ZOX
  ZOX="$(find "$HOME/apps/zoxide/extract" -maxdepth 3 -type f -name zoxide | head -n1 || true)"
  if [ -n "${ZOX:-}" ]; then
    install -m 0755 "$ZOX" "$HOME/bin/zoxide"
  else
    die "zoxide binary not found after extraction"
  fi

  if ! grep -q 'zoxide init zsh' "$HOME/.zshrc" 2>/dev/null; then
    echo 'eval "$(zoxide init zsh)"' >>"$HOME/.zshrc"
  fi
}

# ====== 6) Install exa (deprecated) with graceful fallback to eza ======
install_exa_or_eza() {
  say "Installing exa v0.10.1 (or eza fallback)"
  mkdir -p "$HOME/apps/exa" && cd "$HOME/apps/exa"
  local EXAZIP="exa-linux-x86_64-v0.10.1.zip"
  local EXAURL="https://github.com/ogham/exa/releases/download/v0.10.1/${EXAZIP}"
  local got_exa=0
  rm -f "$EXAZIP"
  if have curl; then
    curl -fL -o "$EXAZIP" "$EXAURL" || true
  else
    wget -O "$EXAZIP" "$EXAURL" || true
  fi

  if [ -f "$EXAZIP" ]; then
    rm -rf "$HOME/apps/exa/exa" "$HOME/apps/exa/bin" || true
    unzip -o "$EXAZIP" || true
    if [ -f "$HOME/apps/exa/bin/exa" ]; then
      ln -sf "$HOME/apps/exa/bin/exa" "$HOME/bin/exa"
      got_exa=1
    elif [ -f "$HOME/apps/exa/exa" ]; then
      ln -sf "$HOME/apps/exa/exa" "$HOME/bin/exa"
      got_exa=1
    fi
  fi

  if [ "$got_exa" -eq 0 ]; then
    say "exa download failed or structure changed; falling back to eza"
    mkdir -p "$HOME/apps/eza" && cd "$HOME/apps/eza"
    local EZAURL="https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz"
    if have curl; then
      curl -fL -o eza.tar.gz "$EZAURL" || true
    else
      wget -O eza.tar.gz "$EZAURL" || true
    fi
    if [ -f eza.tar.gz ]; then
      rm -rf "$HOME/apps/eza/extract" || true
      mkdir -p "$HOME/apps/eza/extract"
      tar -xzf eza.tar.gz -C "$HOME/apps/eza/extract" || true
      local EZABIN
      EZABIN="$(find "$HOME/apps/eza/extract" -maxdepth 3 -type f -name eza | head -n1 || true)"
      if [ -n "${EZABIN:-}" ]; then
        ln -sf "$EZABIN" "$HOME/bin/exa" # still map to exa name for your aliases
      else
        say "eza binary not found; skipping."
      fi
    fi
  fi
}

# ====== 7) Shell aliases and defaults ======
configure_aliases() {
  say "Adding shell aliases to ~/.zshrc"
  touch "$HOME/.zshrc"
  add_alias() {
    local line="$1"
    grep -qxF "$line" "$HOME/.zshrc" 2>/dev/null || echo "$line" >>"$HOME/.zshrc"
  }
  add_alias "alias gs='git status'"
  add_alias "alias ga='git add'"
  add_alias "alias gc='git commit'"
  add_alias "alias ls='exa -al --icons'"
  add_alias "alias ll='exa -l --icons'"
  add_alias "alias vim='nvim'"
}

# ====== 8) LazyVim bootstrap ======
install_lazyvim() {
  say "Installing LazyVim starter"
  if [ -d "$HOME/.config/nvim" ]; then
    mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak.$(date +%s)" || true
  fi
  git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
  rm -rf "$HOME/.config/nvim/.git"

  if [ -f "$SCRIPT_DIR/monokai-pro.lua" ]; then
    mkdir -p "$HOME/.config/nvim/lua/plugins"
    cp "$SCRIPT_DIR/monokai-pro.lua" "$HOME/.config/nvim/lua/plugins/monokai-pro.lua"
  fi
}

main() {
  ensure_bash_login_sources_bashrc
  install_zsh
  configure_bash_to_zsh_handoff
  install_z4h
  install_p10k
  install_neovim
  install_zoxide
  install_exa_or_eza
  configure_aliases
  install_lazyvim
  say "All done! Open a new SSH session or run: exec zsh -l"
}

main "$@"n/env bash
