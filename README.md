# dotfiles

My Linux dev environment, reproducible in one command. Built for exe.dev VMs
(one VM per project) and works on any Ubuntu, including WSL.

## What you get

| Area | Tools |
| --- | --- |
| Shell | zsh (login shell), zsh-autosuggestions, prefix history search on Up/Down, starship, fzf (keybindings), fd, ripgrep, tmux |
| Git | delta as the diff pager, with Dracula syntax highlighting, line numbers, and `n` / `N` navigation between diff sections; also used for `git add -p`; `zdiff3` merge conflict style |
| Node | fnm, latest LTS as default, auto-switch on `.nvmrc`/`.node-version`; pnpm, TypeScript, TS/Vue language servers, vercel, wrangler (Cloudflare), codex |
| Other runtimes | bun, Go (+ gopls, staticcheck, goose), Rust via rustup (+ rust-analyzer, clippy, rustfmt), PHP + Composer + Laravel installer via [php.new](https://php.new) (+ intelephense) |
| AI tools | Agent skills for Claude Code, Codex and opencode via the [skills CLI](https://github.com/vercel-labs/skills) (see below); Claude Code (with my CLAUDE.md and settings; plugins: typescript/gopls/rust-analyzer/php LSPs; ccstatusline with my config), opencode, Antigravity CLI (`agy`) |
| Browsers | agent-browser (+ Chrome for Testing, discovery skill for every agent), Playwright system deps (browsers stay per-project) |
| Extras | turso, bat, lsd, [herdr](https://herdr.dev) (agent-aware multiplexer), herdr-core (`hc`, for the herdr phone app; see below), [T3 Code](https://t3.codes) (as a background service; see below), [Executor](https://executor.sh) (unified MCP gateway on personal VMs; see below); toggle with `EXTRAS` |
| Network | joins my tailnet via exe.dev's Tailscale integration, when it's attached to the VM, with Tailscale SSH on (see below) |

Already in the exe.dev base image and skipped automatically: Go, gh, neovim, uv, docker, Claude Code, Codex, opencode.

## Use it

**Every new exe.dev VM (set once):**

```sh
ssh exe.dev defaults write dev.exe new.setup-script < bootstrap.sh
```

New VMs then clone this repo and run `install.sh` on first boot. Follow along
on the VM with `tail -f ~/dotfiles-bootstrap.log`. One VM only:
`ssh exe.dev new --setup-script /dev/stdin < bootstrap.sh`.

**Work VMs** use the `work` Claude profile (see below):

```sh
sed '2i CLAUDE_PROFILE=work' bootstrap.sh | ssh exe.dev new --setup-script /dev/stdin
```

**Any machine, by hand:**

```sh
git clone https://github.com/leondore/dotfiles ~/.dotfiles
bash ~/.dotfiles/install.sh
```

Re-running is safe: installed tools are skipped and dotfiles re-linked. Individual
download failures don't stop the run; they're listed at the end, so just re-run.
Options: `NODE_VERSION=24` (instead of latest LTS), `PHP_VERSION=8.4`, `EXTRAS="bat"` (or `""`),
`CLAUDE_PROFILE=work`, `TAILSCALE=1` or `0` (default `auto`).
On WSL it refuses to run unless `ALLOW_WSL=1`, since it replaces the Volta-based
`.zshrc` and the `cc-use` `~/.claude` symlink there.

**After the first boot**, log in once per VM: `claude`, `opencode`, `agy`, and (on personal
VMs) `executor login`. Pair T3 Code with each device: `t3 pair --tailscale` (one-time link,
expires in 5 minutes).

**Tailscale** goes through exe.dev's `tailscale-wif` integration (workload identity
federation): the VM trades a short-lived exe.dev token for a tailnet join, so no auth key
lives on it. The integration is attached to the `personal` tag, and `install.sh` joins
whenever it's attached (`TAILSCALE=auto`), as `tag:exe`, with `ephemeral=false` so a VM
keeps its tailnet name; delete removed VMs in the Tailscale console. For a VM without the
tag, attach it and re-run `install.sh`:
`ssh exe.dev integrations attach tailscale-wif vm:<name>`. `TAILSCALE=1` turns a missing
integration into a reported failure instead of a skip; `TAILSCALE=0` never joins. Setup
on the account side, once: `tag:exe` in the policy's `tagOwners`, MagicDNS and HTTPS
certificates on, and a trust credential (OpenID Connect, Auth Keys write, `tag:exe`)
matching the integration ([exe.dev docs](https://exe.dev/docs/integrations-tailscale-wif.md)).

**Tailscale SSH** is turned on once the VM is on the tailnet, since exe.dev VMs run no
sshd. The tailnet policy decides who gets in, so it also needs an SSH rule for the tag;
the default `autogroup:self` rule doesn't cover tagged devices:

```jsonc
{ "action": "accept", "src": ["autogroup:member"], "dst": ["tag:exe"], "users": ["exedev"] }
```

`accept` rather than `check`, because non-interactive clients (the herdr app) can't
complete the browser re-auth that `check` asks for.

**herdr phone app** connects over that SSH and runs `hc connect`: address
`<vm>.<tailnet>.ts.net`, port `22`, user `exedev`. Any key or password the app asks for
is ignored; Tailscale authorizes by tailnet identity.

**T3 Code** runs as a systemd user service on `0.0.0.0:3773`. In a browser it's at
`https://<vm>.exe.xyz:3773/`, behind exe.dev login. The desktop and phone apps can't log
in to exe.dev (the proxy redirects them), so they pair over the tailnet instead, via
`t3 pair --tailscale`, which also maps `https://<vm>.<tailnet>.ts.net/` with Tailscale
Serve. Don't add a VM to the desktop app as an **SSH** environment while the service is
down: it starts its own server, which then holds `~/.t3/userdata` and keeps the service
from starting.

**Executor** ([executor.sh](https://executor.sh)) exposes personal connectors through a
single stdio MCP (`executor mcp`), installed and wired up on **personal VMs only**
(skipped when `CLAUDE_PROFILE=work` or `executor` is omitted from `EXTRAS`). One
`executor login` per VM authenticates all four agents: Claude Code (`~/.claude.json`),
Codex (`~/.codex/config.toml`), opencode (`~/.config/opencode/opencode.jsonc`), and
Antigravity (`~/.gemini/config/mcp_config.json`). Because T3 Code runs Antigravity ACP
with an isolated `GEMINI_HOME` (`~/.t3/userdata/providers/antigravity/<hash>`) and does
not symlink `config/mcp_config.json`, `install.sh` symlinks it to
`~/.gemini/config/mcp_config.json` (if T3 ever overwrites that file when initializing
Antigravity for the first time, re-run `install.sh`).

To identify and revoke VMs individually instead of sharing generic `Executor CLI` device
logins, create a single-org Personal Access Token named after the VM in Executor
(**Connections → Personal access token → Manage tokens**) and set it in both
`~/.zshenv.local` (for shells) and `~/.t3/service.env` (for the T3 Code systemd service,
which doesn't source `~/.zshenv.local`), then restart T3 Code:

```sh
cat <<'EOF' >> ~/.zshenv.local
export EXECUTOR_HOST="https://mcp.executor.sh"
export EXECUTOR_ACCESS_TOKEN="<pat>"
EOF
cat <<'EOF' >> ~/.t3/service.env
EXECUTOR_HOST=https://mcp.executor.sh
EXECUTOR_ACCESS_TOKEN=<pat>
EOF
systemctl --user restart t3code.service
```

**GitHub** goes through exe.dev's GitHub integration: no token or SSH key on the VM.
Each repo needs an integration attached to the VM (`dotfiles` is on `auto:all`), and is
cloned from the proxy, `https://github.int.exe.xyz/<owner>/<repo>.git`. `bootstrap.sh`
moves `~/.dotfiles` to that remote and sets `GH_HOST=github.int.exe.xyz` in
`~/.zshenv.local`, so `gh` works too. A repo whose remote is still `github.com` makes `gh`
refuse to run until it's switched (`git remote set-url origin <proxy url>`). The proxy
covers repo commands (`gh pr`, `gh issue`, `gh repo`), not arbitrary `gh api` calls; for
those, `gh auth login` with a fine-grained token.

## Layout

```
install.sh              installs tools, then symlinks the two trees below
bootstrap.sh            exe.dev setup script (clone + install.sh)
home/                   mirrored into $HOME          (~/.zshrc, ~/.config/starship.toml, ...)
claude/                 mirrored into ~/.claude       (settings.json, CLAUDE.md)
claude-work/            seed for ~/.claude/settings.json on work VMs (copied, not linked)
agents/skills/          my own skills, mirrored into ~/.agents/skills and ~/.claude/skills
githooks/               pre-commit guard for this repo (set as core.hooksPath by install.sh)
packages/node-globals.txt   npm globals
packages/go-tools.txt       go install targets
packages/skills.txt         third-party agent skills (skills CLI)
```

Files are **symlinked**, so editing `~/.zshrc` on a VM edits the repo; commit and push
from there. To add a dotfile, drop it in `home/` at its path relative to `~` and re-run.
Anything a link would overwrite goes to `~/.dotfiles-backup/<timestamp>/`.

Per-machine tweaks that shouldn't be shared go in untracked files:
`~/.zshrc.local`, `~/.zshenv.local`, `~/.gitconfig.local` (e.g. a work email).

A yellow `⚙ N` in the prompt means `~/.dotfiles` has N uncommitted changes, often from a
tool writing to a linked file (e.g. `/model` or `/plugin` editing `settings.json`).

### Claude profiles: personal vs work

`install.sh` takes `CLAUDE_PROFILE=personal` (default) or `work` and remembers it in
`~/.config/dotfiles/profile`, so plain re-runs keep the VM's profile.

- **personal**: everything in `claude/` is linked, as described above.
- **work**: `claude/` is linked **except** `settings.json` and `CLAUDE.md`.
  `~/.claude/settings.json` is a real file, seeded once from `claude-work/settings.json`,
  then edited on the VM and never committed. Work settings collect org details (auto mode
  writes internal hosts, secret names and branches into them), and this repo is public.
  There's no user-level `CLAUDE.md`, since work repos carry their own. Connectors
  (Atlassian, Slack, ...) come with the work account login, and internal MCPs from each
  repo's `.mcp.json`. Executor is also skipped on work VMs (neither installed nor wired
  into any agent).

The pre-commit hook rejects staged lines adding an `autoMode` key, plus any regexes (one
per line) in the untracked `~/.config/dotfiles/blocked-patterns`. Put employer-specific
names there instead of in this repo. Bypass a false positive with `git commit --no-verify`.

### Agent skills

Skills are user-level, shared by every agent and every repo. Codex and opencode read
`~/.agents/skills`; Claude Code only reads `~/.claude/skills`, so each skill lands in both.

- **Third-party skills** are listed in `packages/skills.txt` and installed by
  `install.sh` with the [skills CLI](https://github.com/vercel-labs/skills), which keeps
  one copy in `~/.agents/skills` and links it into `~/.claude/skills`.
  A line is either a whole repo (`cloudflare/skills`), one skill from it
  (`anthropics/skills frontend-design`), or one skill under a new name
  (`some/repo research some-research`), for when two sources ship the same name.
  - Update: `skills update -g` (`skills check -g` to see what's behind). This updates
    installed skills only; to pick up skills a whole repo added since, run
    `skills add <source> -g -y -a claude-code codex`.
  - Add: a line in `skills.txt`, then re-run `install.sh`.
  - Remove: delete the line and run `skills remove -g <name>`; `install.sh` never
    uninstalls. To drop one skill of a whole repo on one VM, just `skills remove -g` it:
    a whole repo isn't reinstalled while any of its skills are.
- **My own skills** go in `agents/skills/<name>/SKILL.md` and are symlinked like the other
  dotfiles, so editing them on a VM edits the repo. Re-run `install.sh` after adding one.

## Notes

- **PATH lives in `.zshenv`, not `.zshrc`**, so non-interactive commands
  (`ssh vm 'pnpm build'`, agents) see the same tools as your terminal.
- **fnm vs Volta:** fnm installs globals per Node version. To keep the Volta feel,
  npm's global prefix is set to `~/.local/share/npm-global`, so global CLIs survive
  switching versions. Change the default with `fnm default <v>`.
- **Turning a plugin off on one VM** (e.g. php-lsp on work VMs): do it at
  project scope, in the repo's `.claude/settings.local.json`:
  `{"enabledPlugins": {"php-lsp@claude-plugins-official": false}}`.
  Disabling at user scope would edit the symlinked `settings.json` in this repo.
- **herdr integrations** (agent state in the sidebar) are wired up by `install.sh`, not
  by running `herdr integration install` yourself: their config entries are tracked here
  (the hook in `claude/settings.json`, the plugin in opencode's `cli.json`), and herdr's
  own Claude installer would add a duplicate, absolute-path hook to the linked file. If
  `git status` ever shows herdr changes after a `herdr update`, discard them and re-run
  `install.sh`.
- **exe.dev's agent notes**: the base image ships a `~/.claude/CLAUDE.md` about the VM
  (HTTPS proxy, documented features only). `install.sh` moves it to
  `~/.claude/rules/exe-dev.md`, which Claude Code loads alongside your `CLAUDE.md`, so it
  survives the link on both profiles and stays local to the VM.
- **`systemctl --user` env in `.zshenv`**: processes daemonized outside a login session
  (the herdr server) lose `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS`, so every shell
  under them fails with "Failed to connect to bus". `.zshenv` fills them in when missing.
- **Fonts** are rendered by the terminal you connect from, so the coding font only
  needs to be installed on your own computer.
- **No secrets in this repo** (it's public). Credentials, `~/.claude.json`,
  `~/.npmrc` and shell history stay untracked.
