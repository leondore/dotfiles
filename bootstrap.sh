#!/bin/bash
# exe.dev setup script: runs once on the first boot of a new VM.
# Make it the default for every new VM:
#   ssh exe.dev defaults write dev.exe new.setup-script < bootstrap.sh
# Progress/output ends up in ~/dotfiles-bootstrap.log on the VM.
set -euo pipefail

REPO="${DOTFILES_REPO:-https://github.com/leondore/dotfiles.git}"
VM_USER="${DOTFILES_USER:-exedev}"

run() {
  set -euo pipefail
  export HOME="${HOME:-$(getent passwd "$(id -un)" | cut -d: -f6)}"
  cd "$HOME"
  {
    echo "[$(date -Is)] dotfiles bootstrap starting"
    if [ -d "$HOME/.dotfiles/.git" ]; then
      git -C "$HOME/.dotfiles" pull -q --ff-only
    else
      git clone -q --depth 1 "$1" "$HOME/.dotfiles"
    fi
    bash "$HOME/.dotfiles/install.sh"
    echo "[$(date -Is)] dotfiles bootstrap finished"
  } 2>&1 | tee -a "$HOME/dotfiles-bootstrap.log"
}

if [ "$(id -u)" -eq 0 ]; then
  sudo -u "$VM_USER" -H bash -c "$(declare -f run); run '$REPO'"
else
  run "$REPO"
fi
