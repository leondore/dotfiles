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

# systemd user session vars. Normally set by pam_systemd on SSH login, but
# processes daemonized outside a login session (e.g. herdr server) lose them,
# which breaks `systemctl --user` for every shell spawned underneath.
if [[ -z "$XDG_RUNTIME_DIR" && -d "/run/user/$UID" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$UID"
fi
if [[ -z "$DBUS_SESSION_BUS_ADDRESS" && -S "$XDG_RUNTIME_DIR/bus" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi

# Machine-specific overrides (not tracked)
[[ -f "$HOME/.zshenv.local" ]] && source "$HOME/.zshenv.local"
