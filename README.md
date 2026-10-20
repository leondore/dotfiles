# dotfiles

My Linux dev environment, reproducible in one command. Built for exe.dev VMs
(one VM per project) and works on any Ubuntu, including WSL.

## What you get

| Area | Tools |
| --- | --- |
| Shell | zsh (login shell), zsh-autosuggestions, starship, fzf (keybindings), fd, ripgrep, tmux |
| Node | fnm, latest LTS as default, auto-switch on `.nvmrc`/`.node-version`; pnpm, TypeScript, TS/Vue language servers, vercel, codex |
| Other runtimes | bun, Go (+ gopls, staticcheck, goose), Rust via rustup (+ rust-analyzer, clippy, rustfmt), PHP + Composer + Laravel installer via [php.new](https://php.new) (+ intelephense) |
| AI tools | Claude Code (with my CLAUDE.md, settings and skills; plugins: typescript/gopls/rust-analyzer/php LSPs, mattpocock-skills; ccstatusline with my config), opencode |
| Browsers | agent-browser (+ Chrome for Testing, discovery skill for Claude), Playwright system deps (browsers stay per-project) |
| Extras | deno, turso, bat (toggle with `EXTRAS`) |

Already in the exe.dev base image and skipped automatically: Go, gh, neovim, uv, docker, Claude Code, Codex, opencode.

## Use it

**Every new exe.dev VM (set once):**

```sh
ssh exe.dev defaults write dev.exe new.setup-script < bootstrap.sh
```

New VMs then clone this repo and run `install.sh` on first boot. Follow along
on the VM with `tail -f ~/dotfiles-bootstrap.log`. One VM only:
`ssh exe.dev new --setup-script /dev/stdin < bootstrap.sh`.

**Any machine, by hand:**

```sh
git clone https://github.com/leondore/dotfiles ~/.dotfiles
bash ~/.dotfiles/install.sh
```

Re-running is safe: installed tools are skipped and dotfiles re-linked. Individual
download failures don't stop the run; they're listed at the end, so just re-run.
Options: `NODE_VERSION=24` (instead of latest LTS), `PHP_VERSION=8.4`, `EXTRAS="deno"` (or `""`).
On WSL it refuses to run unless `ALLOW_WSL=1`, since it replaces the Volta-based
`.zshrc` and the `cc-use` `~/.claude` symlink there.

**After the first boot**, log in once per VM: `claude`, `opencode`. GitHub access
comes from the exe.dev GitHub integration.

## Layout

```
install.sh              installs tools, then symlinks the two trees below
bootstrap.sh            exe.dev setup script (clone + install.sh)
home/                   mirrored into $HOME          (~/.zshrc, ~/.config/starship.toml, ...)
claude/                 mirrored into ~/.claude       (settings.json, CLAUDE.md, skills/)
packages/node-globals.txt   npm globals
packages/go-tools.txt       go install targets
```

Files are **symlinked**, so editing `~/.zshrc` on a VM edits the repo; commit and push
from there. To add a dotfile, drop it in `home/` at its path relative to `~` and re-run.
Anything a link would overwrite goes to `~/.dotfiles-backup/<timestamp>/`.

Per-machine tweaks that shouldn't be shared go in untracked files:
`~/.zshrc.local`, `~/.zshenv.local`, `~/.gitconfig.local` (e.g. a work email).

## Notes

- **PATH lives in `.zshenv`, not `.zshrc`**, so non-interactive commands
  (`ssh vm 'pnpm build'`, agents) see the same tools as your terminal.
- **fnm vs Volta:** fnm installs globals per Node version. To keep the Volta feel,
  npm's global prefix is set to `~/.local/share/npm-global`, so global CLIs survive
  switching versions. Change the default with `fnm default <v>`.
- **Turning a plugin off on one VM** (e.g. mattpocock-skills on work VMs): do it at
  project scope, in the repo's `.claude/settings.local.json`:
  `{"enabledPlugins": {"mattpocock-skills@claude-plugins-official": false}}`.
  Disabling at user scope would edit the symlinked `settings.json` in this repo.
- **Fonts** are rendered by the terminal you connect from, so the coding font only
  needs to be installed on your own computer.
- **No secrets in this repo** (it's public). Credentials, `~/.claude.json`,
  `~/.npmrc` and shell history stay untracked.
