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
PHP_VERSION="${PHP_VERSION:-8.5}"            # php.new / herd-lite build (falls back to 8.4 if unavailable)
EXTRAS="${EXTRAS:-turso bat lsd herdr}"      # optional tools, space-separated
NPM_GLOBAL="$HOME/.local/share/npm-global"   # npm globals live outside fnm's per-version dirs
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

# Claude profile: "personal" links claude/ as-is; "work" keeps settings.json and CLAUDE.md
# out of the repo (see the linking step). Remembered per machine so a plain re-run
# never swaps a work VM back to the personal settings.
PROFILE_FILE="$HOME/.config/dotfiles/profile"
CLAUDE_PROFILE="${CLAUDE_PROFILE:-$(cat "$PROFILE_FILE" 2>/dev/null || echo personal)}"
case "$CLAUDE_PROFILE" in
  personal|work) ;;
  *) echo "CLAUDE_PROFILE must be 'personal' or 'work', got '$CLAUDE_PROFILE'" >&2; exit 1 ;;
esac

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
export PATH="$HOME/.local/bin:$NPM_GLOBAL/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:$HOME/.bun/bin:$HOME/.opencode/bin:$HOME/.turso:$PATH"

case "$(uname -m)" in
  x86_64)  GOARCH=amd64 ;;
  aarch64) GOARCH=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# --- System packages ---------------------------------------------------------
log "System packages"
APT_PKGS=(zsh git curl ca-certificates unzip build-essential pkg-config libssl-dev jq ripgrep fd-find tmux)
want bat && APT_PKGS+=(bat)
want lsd && APT_PKGS+=(lsd)
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
# Ubuntu ships bat as `batcat` and fd as `fdfind`
if want bat && has batcat && ! has bat; then ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"; fi
if has fdfind && ! has fd; then ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"; fi

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
# Own copy of docker's completion: ~/.zsh/completion comes first in fpath, so compinit
# never reads Docker Desktop's vendor-completions/_docker on WSL, a symlink into a mount
# that only exists while Docker Desktop runs (compinit errors on it otherwise).
if has docker && docker completion zsh > "$HOME/.zsh/completion/_docker.tmp" 2>/dev/null; then
  mv "$HOME/.zsh/completion/_docker.tmp" "$HOME/.zsh/completion/_docker"
else
  rm -f "$HOME/.zsh/completion/_docker.tmp"
fi

# --- starship --------------------------------------------------------------------
log "starship"
if has starship; then skip starship; else
  try installer https://starship.rs/install.sh sh -y -b "$HOME/.local/bin"
fi

# --- fzf -------------------------------------------------------------------------
# From GitHub releases: Ubuntu's package is too old for `fzf --zsh` (needs 0.48+).
# Lands in ~/.local/bin, which shadows an apt-installed /usr/bin/fzf.
log "fzf"
install_fzf() {
  local ver
  ver="$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest | jq -r .tag_name)" &&
  curl -fsSL "https://github.com/junegunn/fzf/releases/download/${ver}/fzf-${ver#v}-linux_${GOARCH}.tar.gz" |
    tar -xz -C "$HOME/.local/bin" fzf
}
if has fzf && fzf --zsh >/dev/null 2>&1; then skip "fzf ($(fzf --version | cut -d' ' -f1))"; else try install_fzf; fi

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

# --- PHP (php.new) -------------------------------------------------------------------
# Static PHP + Composer + Laravel installer from the same downloads php.new uses. Done
# by hand because the php.new script calls `clear` (fatal without a TTY under set -e),
# doesn't fail on HTTP errors, and edits rc files. PATH/PHP_INI_SCAN_DIR are in .zshenv.
log "PHP, Composer, Laravel installer"
HERD_LITE="$HOME/.config/herd-lite/bin"
install_php() {
  local base=https://download.herdphp.com arch=x64 v
  [ "$GOARCH" = arm64 ] && arch=arm64
  mkdir -p "$HERD_LITE" &&
  for v in "$PHP_VERSION" 8.4; do
    curl -fsSL "$base/herd-lite/linux/$arch/$v/php" -o "$HERD_LITE/php" && break
  done && [ -s "$HERD_LITE/php" ] &&
  curl -fsSL "$base/herd-lite/composer" -o "$HERD_LITE/composer" &&
  curl -fsSL "$base/resources/laravel" -o "$HERD_LITE/laravel" &&
  curl -fsSL https://curl.se/ca/cacert.pem -o "$HERD_LITE/cacert.pem" &&
  chmod +x "$HERD_LITE/php" "$HERD_LITE/composer" "$HERD_LITE/laravel" &&
  if [ ! -f "$HERD_LITE/php.ini" ]; then
    printf 'curl.cainfo=%s\nopenssl.cafile=%s\npcre.jit=0\n' "$HERD_LITE/cacert.pem" "$HERD_LITE/cacert.pem" > "$HERD_LITE/php.ini"
  fi &&
  echo "    $("$HERD_LITE/php" -r 'echo "php ", PHP_VERSION;')" &&
  # herd-lite's Composer build lags behind; bring it to the latest stable
  "$HERD_LITE/php" "$HERD_LITE/composer" self-update --stable -q
}
export PATH="$HERD_LITE:$PATH" PHP_INI_SCAN_DIR="$HERD_LITE"
if has php && has composer; then skip "php ($(php -r 'echo PHP_VERSION;'))"; else try install_php; fi

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

# --- Browsers for agents and e2e ---------------------------------------------------------
# agent-browser's Chrome (Chrome for Testing) plus the system libraries headless Chromium
# needs. Playwright's browser binaries are per-project (tied to its version), but its
# install-deps covers the apt side once so e2e runs don't stop at a sudo prompt.
if has agent-browser; then
  log "agent-browser Chrome + system deps"
  if compgen -G "$HOME/.agent-browser/browsers/*" >/dev/null; then skip "agent-browser Chrome"
  else try agent-browser install --with-deps; fi
fi
if has pnpm && [ ! -f "$HOME/.cache/.playwright-deps-done" ]; then
  log "Playwright system deps"
  try bash -c 'pnpm dlx playwright install-deps chromium && mkdir -p ~/.cache && touch ~/.cache/.playwright-deps-done'
fi

# --- Extras ------------------------------------------------------------------------------
if want herdr; then
  # Agent-aware multiplexer (tmux stays installed as the fallback). The installer
  # verifies the binary's SHA-256 and drops it in ~/.local/bin; `herdr update` updates it.
  log "herdr"
  if has herdr; then skip herdr; else try installer https://herdr.dev/install.sh sh; fi
fi
if want turso; then
  log "turso"
  if has turso; then skip turso; else try installer https://get.tur.so/install.sh bash; fi
fi

# --- Dotfiles ------------------------------------------------------------------------------
# Symlink every file under home/ into $HOME and every file under claude/ into ~/.claude.
# Existing real files are moved to ~/.dotfiles-backup/<timestamp>/ first. Paths listed
# after the two roots are skipped, and a stale link from an earlier run is removed.
backup() {
  mkdir -p "$BACKUP_DIR/$(dirname "${1#"$HOME"/}")"
  mv "$1" "$BACKUP_DIR/${1#"$HOME"/}"
  echo "    backed up ~/${1#"$HOME"/}"
}
link_tree() {
  local src_root="$1" dst_root="$2" src rel dst
  local skip=" ${*:3} "
  while IFS= read -r -d '' src; do
    rel="${src#"$src_root"/}"
    dst="$dst_root/$rel"
    if [[ "$skip" == *" $rel "* ]]; then
      if [ "$(readlink "$dst" 2>/dev/null)" = "$src" ]; then backup "$dst"; fi
      continue
    fi
    mkdir -p "$(dirname "$dst")"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then continue; fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then backup "$dst"; fi
    ln -s "$src" "$dst"
    echo "    linked ~/${dst#"$HOME"/}"
  done < <(find "$src_root" -type f -print0)
}

log "Linking dotfiles (Claude profile: $CLAUDE_PROFILE)"
mkdir -p "$(dirname "$PROFILE_FILE")" && echo "$CLAUDE_PROFILE" > "$PROFILE_FILE"
# ~/.claude must be a real directory (Claude Code keeps state there), not a symlink.
if [ -L "$HOME/.claude" ]; then mkdir -p "$BACKUP_DIR"; mv "$HOME/.claude" "$BACKUP_DIR/.claude-link"; fi
mkdir -p "$HOME/.claude"
# exe.dev's image ships a ~/.claude/CLAUDE.md telling agents about the VM (HTTPS proxy,
# documented features only). Keep it as a user rule instead of losing it to the link.
if [ -f "$HOME/.claude/CLAUDE.md" ] && [ ! -L "$HOME/.claude/CLAUDE.md" ] &&
   grep -q 'exe\.dev VM' "$HOME/.claude/CLAUDE.md"; then
  mkdir -p "$HOME/.claude/rules"
  mv "$HOME/.claude/CLAUDE.md" "$HOME/.claude/rules/exe-dev.md"
  echo "    moved exe.dev's ~/.claude/CLAUDE.md to ~/.claude/rules/exe-dev.md"
fi
link_tree "$DOTFILES/home" "$HOME"
if [ "$CLAUDE_PROFILE" = work ]; then
  # Work settings are edited on the VM and never tracked: auto mode and other tools write
  # org details (internal hosts, secret names) into them, and this repo is public. They're
  # seeded once from claude-work/settings.json. Work CLAUDE.md files are per repo.
  link_tree "$DOTFILES/claude" "$HOME/.claude" settings.json CLAUDE.md
  if [ -f "$HOME/.claude/settings.json" ] && [ ! -L "$HOME/.claude/settings.json" ]; then
    echo "    kept local ~/.claude/settings.json"
  else
    if [ -L "$HOME/.claude/settings.json" ]; then backup "$HOME/.claude/settings.json"; fi
    cp "$DOTFILES/claude-work/settings.json" "$HOME/.claude/settings.json"
    echo "    seeded ~/.claude/settings.json from claude-work/"
  fi
else
  link_tree "$DOTFILES/claude" "$HOME/.claude"
fi

# Pre-commit guard against committing work config to this public repo.
git -C "$DOTFILES" config core.hooksPath githooks

# herdr agent-state integrations. Their config entries are tracked in this repo
# (Claude hook in claude/settings.json, opencode plugin in cli.json), so herdr must
# not write to the linked files: for Claude it would add a second hook with an
# absolute path, so only its hook script is taken, from a scratch HOME.
herdr_claude() {
  local scratch
  scratch="$(mktemp -d)" && mkdir -p "$scratch/.claude" &&
  HOME="$scratch" herdr integration install claude >/dev/null &&
  mkdir -p "$HOME/.claude/hooks" &&
  cp "$scratch/.claude/hooks/herdr-agent-state.sh" "$HOME/.claude/hooks/" &&
  rm -rf "$scratch"
}
if has herdr; then
  log "herdr integrations"
  try herdr_claude
  try herdr integration install opencode   # cli.json entry already present, left untouched
  mkdir -p "${CODEX_HOME:-$HOME/.codex}" && try herdr integration install codex
  herdr integration status 2>/dev/null | grep -E '^(claude|codex|opencode):' | sed 's/^/    /' || true
fi

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
