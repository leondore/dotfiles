#!/usr/bin/env bash
# Leon's dev environment: idempotent setup for Ubuntu (exe.dev VMs, WSL).
# Safe to re-run: anything already installed is skipped, dotfiles are re-linked.
#
#   bash install.sh                     # everything
#   NODE_VERSION=24 bash install.sh     # pin a Node major instead of latest LTS
#   EXTRAS="" bash install.sh           # skip the optional extras
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
NODE_VERSION="${NODE_VERSION:-lts}"          # "lts" or any fnm version spec (24, 22.23.3, ...)
EXTRAS="${EXTRAS:-deno turso bat}"           # optional tools, space-separated
NPM_GLOBAL="$HOME/.local/share/npm-global"   # npm globals live outside fnm's per-version dirs
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
skip() { printf '    \033[2m%s already installed, skipping\033[0m\n' "$1"; }
has()  { command -v "$1" >/dev/null 2>&1; }
want() { [[ " $EXTRAS " == *" $1 "* ]]; }

# One flaky download shouldn't stop the rest of the setup: non-critical steps go
# through `try`, failures are collected and reported at the end.
FAILED=()
try() { "$@" || { FAILED+=("$*"); printf '    \033[1;33m! failed:\033[0m %s\n' "$*"; }; }

# Third-party installers love appending to ~/.zshrc / ~/.bashrc. Running them
# with SHELL=/bin/sh makes most of them leave rc files alone; the dotfiles are
# linked last anyway, so anything they write gets backed up and replaced.
installer() { curl -fsSL "$1" | SHELL=/bin/sh "${2:-bash}" -s -- "${@:3}"; }

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user (it uses sudo where needed), not as root." >&2
  exit 1
fi

# On WSL this would replace the current Volta-based .zshrc and the cc-use ~/.claude
# symlink, so it only runs there when explicitly asked to.
if grep -qi microsoft /proc/version 2>/dev/null && [ "${ALLOW_WSL:-}" != 1 ]; then
  echo "WSL detected. This replaces ~/.zshrc and turns ~/.claude into a real dir (old ones get backed up)." >&2
  echo "Re-run with ALLOW_WSL=1 once you're ready to switch WSL over too." >&2
  exit 1
fi

mkdir -p "$HOME/.local/bin" "$HOME/.zsh/completion" "$NPM_GLOBAL"
export PATH="$HOME/.local/bin:$NPM_GLOBAL/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:$HOME/.bun/bin:$HOME/.deno/bin:$HOME/.opencode/bin:$HOME/.turso:$PATH"

case "$(uname -m)" in
  x86_64)  GOARCH=amd64 ;;
  aarch64) GOARCH=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# --- System packages ---------------------------------------------------------
log "System packages"
APT_PKGS=(zsh git curl ca-certificates unzip build-essential pkg-config libssl-dev jq ripgrep)
want bat && APT_PKGS+=(bat)
missing=()
for p in "${APT_PKGS[@]}"; do
  [ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" = "install ok installed" ] || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "${missing[@]}"
else
  skip "apt packages"
fi
# Ubuntu ships bat as `batcat`
if want bat && has batcat && ! has bat; then ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"; fi

# --- zsh -----------------------------------------------------------------------
log "zsh"
ZSH_BIN="$(command -v zsh)"
if [ "$(getent passwd "$(id -un)" | cut -d: -f7)" != "$ZSH_BIN" ]; then
  sudo chsh -s "$ZSH_BIN" "$(id -un)"
else
  skip "zsh as login shell"
fi
if [ -d "$HOME/.zsh/zsh-autosuggestions/.git" ]; then
  git -C "$HOME/.zsh/zsh-autosuggestions" pull -q --ff-only || true
else
  try git clone -q --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/zsh-autosuggestions"
fi

# --- starship --------------------------------------------------------------------
log "starship"
if has starship; then skip starship; else
  try installer https://starship.rs/install.sh sh -y -b "$HOME/.local/bin"
fi

# --- Node via fnm ------------------------------------------------------------------
log "fnm + Node ($NODE_VERSION)"
if has fnm; then skip fnm; else
  try installer https://fnm.vercel.app/install bash --install-dir "$HOME/.local/bin" --skip-shell
fi
# (errexit is off inside functions run via `try`, hence the && chain)
setup_node() {
  local alias="$NODE_VERSION"
  eval "$(fnm env --shell bash)" &&
  if [ "$NODE_VERSION" = "lts" ]; then fnm install --lts && alias=lts-latest
  else fnm install "$NODE_VERSION"; fi &&
  fnm default "$alias" &&
  fnm use default >/dev/null &&
  fnm completions --shell zsh > "$HOME/.zsh/completion/_fnm" &&
  echo "    node $(node --version)" &&
  # Keep npm globals in one fixed prefix so they survive switching Node versions
  # (this is what Volta did for you implicitly).
  npm config set prefix "$NPM_GLOBAL"
}
if has fnm && try setup_node && has npm; then
  log "npm globals"
  while read -r pkg bin _; do
    [[ -z "${pkg:-}" || "$pkg" == \#* ]] && continue
    if has "${bin:-$pkg}"; then skip "$pkg"; else try npm install -g --no-fund --no-audit "$pkg"; fi
  done < "$DOTFILES/packages/node-globals.txt"
fi

# --- bun ---------------------------------------------------------------------------
log "bun"
if has bun; then skip bun; else try installer https://bun.sh/install bash; fi

# --- Go ----------------------------------------------------------------------------
log "Go"
install_go() {
  local ver
  ver="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)" &&
  curl -fsSL "https://go.dev/dl/${ver}.linux-${GOARCH}.tar.gz" -o /tmp/go.tgz &&
  sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go.tgz && rm /tmp/go.tgz
}
if has go; then skip "go ($(go version | awk '{print $3}'))"; else try install_go; fi
if has go; then
  while read -r mod bin _; do
    [[ -z "${mod:-}" || "$mod" == \#* ]] && continue
    if has "$bin"; then skip "$bin"; else echo "    go install $mod"; try go install "$mod"; fi
  done < "$DOTFILES/packages/go-tools.txt"
fi

# --- Rust ----------------------------------------------------------------------------
log "Rust"
if has rustup; then skip rustup; else
  try installer https://sh.rustup.rs sh -y --no-modify-path --profile default
fi
if has rustup; then rustup component add rust-analyzer clippy rustfmt >/dev/null 2>&1 || true; fi

# --- AI coding tools -------------------------------------------------------------------
log "Claude Code"
if has claude; then skip claude; else try installer https://claude.ai/install.sh bash; fi

log "opencode"
if has opencode; then skip opencode; else try installer https://opencode.ai/install bash; fi

# Context7 MCP through the exe.dev `context7` integration, which injects the API key
# at the network edge, so the key never lives on the VM (see README). exe.dev only.
CONTEXT7_MCP_URL="${CONTEXT7_MCP_URL:-http://context7.int.exe.xyz/mcp}"
if { [ -d /exe.dev ] || [ -n "${EXEUNTU:-}" ]; } && has claude; then
  log "Context7 MCP"
  if claude mcp get context7 >/dev/null 2>&1; then skip "context7 MCP server"; else
    try claude mcp add --scope user --transport http context7 "$CONTEXT7_MCP_URL"
  fi
fi

# --- Extras ------------------------------------------------------------------------------
if want deno; then
  log "deno"
  if has deno; then skip deno; else try installer https://deno.land/install.sh sh -y --no-modify-path; fi
  if has deno; then deno completions zsh > "$HOME/.zsh/completion/_deno" 2>/dev/null || true; fi
fi
if want turso; then
  log "turso"
  if has turso; then skip turso; else try installer https://get.tur.so/install.sh bash; fi
fi

# --- Dotfiles ------------------------------------------------------------------------------
# Symlink every file under home/ into $HOME and every file under claude/ into ~/.claude.
# Existing real files are moved to ~/.dotfiles-backup/<timestamp>/ first.
link_tree() {
  local src_root="$1" dst_root="$2" src rel dst
  while IFS= read -r -d '' src; do
    rel="${src#"$src_root"/}"
    dst="$dst_root/$rel"
    mkdir -p "$(dirname "$dst")"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then continue; fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      mkdir -p "$BACKUP_DIR/$(dirname "${dst#"$HOME"/}")"
      mv "$dst" "$BACKUP_DIR/${dst#"$HOME"/}"
      echo "    backed up ~/${dst#"$HOME"/}"
    fi
    ln -s "$src" "$dst"
    echo "    linked ~/${dst#"$HOME"/}"
  done < <(find "$src_root" -type f -print0)
}

log "Linking dotfiles"
# ~/.claude must be a real directory (Claude Code keeps state there), not a symlink.
if [ -L "$HOME/.claude" ]; then mkdir -p "$BACKUP_DIR"; mv "$HOME/.claude" "$BACKUP_DIR/.claude-link"; fi
mkdir -p "$HOME/.claude"
link_tree "$DOTFILES/home" "$HOME"
link_tree "$DOTFILES/claude" "$HOME/.claude"

if [ ${#FAILED[@]} -gt 0 ]; then
  log "Finished with ${#FAILED[@]} failure(s); re-run install.sh to retry:"
  printf '    - %s\n' "${FAILED[@]}"
  exit 1
fi

log "Done"
cat <<EOF
    Open a new shell (or run: exec zsh) to pick everything up.
    First-run logins still needed on each VM: claude, opencode (gh is handled by the exe.dev GitHub integration).
EOF
