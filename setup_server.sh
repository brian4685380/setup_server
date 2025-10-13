#!/usr/bin/env bash
set -euo pipefail

# ====== helpers ======
say() { printf "\n\033[1m==> %s\033[0m\n" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Ensure ~/bin exists and is first on PATH (for this run and future shells)
mkdir -p "$HOME/bin"
export PATH="$HOME/bin:$PATH"
grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/bin:$PATH"' >>"$HOME/.bashrc"
grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null || echo 'export PATH="$HOME/bin:$PATH"' >>"$HOME/.zshrc"

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
  make -j"$(getconf _NPROCESSORS_ONLN || echo 1)"
  make install
  cd "$HOME"
  rm -rf zsh-src zsh.tar || true

  # bash → zsh handoff (use the freshly built one if available)
  if ! grep -q 'exec .*zsh -l' "$HOME/.bashrc" 2>/dev/null; then
    cat >>"$HOME/.bashrc" <<'BRC'
# auto-switch to zsh for interactive shells
if [ -t 1 ]; then
  if [ -x "$HOME/bin/zsh" ]; then
    exec "$HOME/bin/zsh" -l
  elif command -v zsh >/dev/null 2>&1; then
    exec zsh -l
  fi
fi
BRC
  fi
}

# ====== 2) Install zsh4humans (v5) ======
install_z4h() {
  say "Installing zsh4humans v5"
  # Run installer via curl or wget
  if have curl; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install)"
  else
    sh -c "$(wget -O- https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install)"
  fi
  # Ensure PATH and zoxide init lines exist (added later too)
  grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null || echo 'export PATH="$HOME/bin:$PATH"' >>"$HOME/.zshrc"
}

# ====== 3) Powerlevel10k config ======
install_p10k() {
  say "Configuring Powerlevel10k"
  # Only copy if source exists in CWD
  if [ -f "$HOME/.p10k.zsh" ]; then
    say "~/.p10k.zsh already present. Skipping copy."
  elif [ -f "./.p10k.zsh" ]; then
    cp "./.p10k.zsh" "$HOME/.p10k.zsh"
  else
    say "No .p10k.zsh found in current directory; skipping."
  fi

  # Make sure zshrc loads it (z4h usually handles this, but ensure)
  if ! grep -q '\.p10k\.zsh' "$HOME/.zshrc" 2>/dev/null; then
    cat >>"$HOME/.zshrc" <<'ZRC'
# Load Powerlevel10k config if present
[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
ZRC
  fi
}

# ====== 4) Install Neovim to ~/apps and symlink to ~/bin ======
install_neovim() {
  say "Installing Neovim v0.11.4 (linux64)"
  mkdir -p "$HOME/apps" && cd "$HOME/apps"
  local NVPKG="nvim-linux64.tar.gz"
  rm -f "$NVPKG"
  if have curl; then
    curl -fL -o "$NVPKG" "https://github.com/neovim/neovim/releases/download/v0.11.4/nvim-linux64.tar.gz"
  else
    wget -O "$NVPKG" "https://github.com/neovim/neovim/releases/download/v0.11.4/nvim-linux64.tar.gz"
  fi
  rm -rf "$HOME/apps/nvim-linux64"
  tar xzf "$NVPKG"
  ln -sf "$HOME/apps/nvim-linux64/bin/nvim" "$HOME/bin/nvim"
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
  rm -rf "$HOME/apps/zoxide/zoxide-0.9.8-x86_64-unknown-linux-musl" || true
  tar -xzf "$ZO"
  # Some tarballs nest the binary; locate it robustly
  local ZOX
  ZOX="$(find "$PWD" -maxdepth 2 -type f -name zoxide | head -n1 || true)"
  if [ -n "${ZOX:-}" ]; then
    install -m 0755 "$ZOX" "$HOME/bin/zoxide"
  else
    say "zoxide binary not found after extraction"
    exit 1
  fi
  # Shell init
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
    unzip -o "$EXAZIP"
    # Older zips contain bin/exa; newer might have just "exa"
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
    local EZAURL
    # Try a common static build; adjust if needed per distro/arch
    if have curl; then
      EZAURL="https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz"
      curl -fL -o eza.tar.gz "$EZAURL" || true
    else
      EZAURL="https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz"
      wget -O eza.tar.gz "$EZAURL" || true
    fi
    if [ -f eza.tar.gz ]; then
      tar -xzf eza.tar.gz
      local EZABIN
      EZABIN="$(find "$PWD" -maxdepth 2 -type f -name eza | head -n1 || true)"
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
  # Backup existing config if present
  if [ -d "$HOME/.config/nvim" ]; then
    mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak.$(date +%s)" || true
  fi
  git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
  rm -rf "$HOME/.config/nvim/.git"
  # Add Monokai Pro plugin file if provided next to script
  if [ -f "./monokai-pro.lua" ]; then
    mkdir -p "$HOME/.config/nvim/lua/plugins"
    cp "./monokai-pro.lua" "$HOME/.config/nvim/lua/plugins/monokai-pro.lua"
  fi
}

main() {
  install_zsh
  install_z4h
  install_p10k
  install_neovim
  install_zoxide
  install_exa_or_eza
  configure_aliases
  install_lazyvim
  say "All done! Start a new shell or run: exec zsh -l"
}

main "$@"
