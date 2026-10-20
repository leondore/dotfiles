# Read by EVERY zsh, including non-interactive ones (`ssh vm 'pnpm build'`,
# agents running commands). Keep PATH/env here; interactive stuff goes in .zshrc.
typeset -U path PATH

export GOPATH="$HOME/go"
export BUN_INSTALL="$HOME/.bun"
export CODEX_HOME="$HOME/.codex"
export EDITOR=nvim
export PHP_INI_SCAN_DIR="$HOME/.config/herd-lite/bin"   # php.new php.ini (CA bundle)

path=(
  "$HOME/.local/bin"
  "$HOME/.config/herd-lite/bin"
  "$HOME/.local/share/npm-global/bin"
  "$BUN_INSTALL/bin"
  "$HOME/.cargo/bin"
  "$GOPATH/bin"
  /usr/local/go/bin
  "$HOME/.opencode/bin"
  "$HOME/.turso"
  $path
)

# Default Node for non-interactive shells (interactive ones get --use-on-cd in .zshrc).
if [[ ! -o interactive ]] && (( $+commands[fnm] )); then
  eval "$(fnm env --shell zsh)"
fi

# Machine-specific overrides (not tracked)
[[ -f "$HOME/.zshenv.local" ]] && source "$HOME/.zshenv.local"
