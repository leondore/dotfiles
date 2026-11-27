# dotfiles

My Linux dev environment, reproducible in one command. Built for exe.dev VMs
(one VM per project) and works on any Ubuntu, including WSL.

## What you get

| Area | Tools |
| --- | --- |
| Shell | zsh (login shell), zsh-autosuggestions, prefix history search on Up/Down, starship, fzf (keybindings), fd, ripgrep, tmux |
| Git | delta as the diff pager, with Dracula syntax highlighting, line numbers, and `n` / `N` navigation between diff sections; also used for `git add -p`; `zdiff3` merge conflict style |
| Node | fnm, latest LTS as default, auto-switch on `.nvmrc`/`.node-version`; pnpm, TypeScript, TS/Vue language servers; vercel, wrangler (Cloudflare) and codex on personal VMs, yarn on work VMs |
| Other runtimes | bun, Go (+ gopls, staticcheck, goose), Rust via rustup (+ rust-analyzer, clippy, rustfmt), PHP + Composer + Laravel installer via [php.new](https://php.new) (+ intelephense) |
| AI tools | Agent skills for Claude Code, Codex, opencode and Antigravity (`sync-skill-packs`, [skills CLI](https://github.com/vercel-labs/skills), `pick-skills`; see below); Claude Code (with my CLAUDE.md and settings; plugins: typescript/gopls/rust-analyzer/php LSPs; ccstatusline with my config), opencode, Antigravity CLI (`agy`) |
| Browsers | agent-browser (+ Chrome for Testing; install its skill per project with `pick-skills`), chrome-devtools MCP for Claude Code (its own Chrome: headed through WSLg on WSL, headless on VMs), Playwright system deps (browsers stay per-project) |
| Extras | turso, bat, lsd, [herdr](https://herdr.dev) (agent-aware multiplexer), herdr-core (`hc`, for the herdr phone app; see below), [T3 Code](https://t3.codes) (as a background service; see below), [Executor](https://executor.sh) (unified MCP gateway on personal VMs; see below) |
| Network | joins my tailnet via exe.dev's Tailscale integration, when it's attached to the VM, with Tailscale SSH on (see below) |

That's the personal profile. The runtimes, opencode, tmux and the extras are optional
tools, and work VMs get fewer of them (see **Profiles** below).

Already in the exe.dev base image and skipped automatically: Go, gh, neovim, uv, docker,
Claude Code, Codex, opencode. They're on every VM, whichever tools are picked.

## Use it

**Every new exe.dev VM (set once):**

```sh
ssh exe.dev defaults write dev.exe new.setup-script < bootstrap.sh
```

New VMs then clone this repo and run `install.sh` on first boot. Follow along
on the VM with `tail -f ~/dotfiles-bootstrap.log`. One VM only:
`ssh exe.dev new --setup-script /dev/stdin < bootstrap.sh`.

**Work VMs** use the `work` profile (see below):

```sh
sed '2i CLAUDE_PROFILE=work' bootstrap.sh | ssh exe.dev new --setup-script /dev/stdin
```

Another tool set for one VM goes in the same way, e.g. `sed '2i TOOLS="go php bat"'`.

**Any machine, by hand:**

```sh
git clone https://github.com/leondore/dotfiles ~/.dotfiles
bash ~/.dotfiles/install.sh
```

Re-running is safe: installed tools are skipped and dotfiles re-linked. Individual
download failures don't stop the run; they're listed at the end, so just re-run.
Options: `CLAUDE_PROFILE=work`, `TOOLS="go php"` (or `""`; see **Profiles**),
`NODE_VERSION=24` (instead of latest LTS), `PHP_VERSION=8.4`, `TAILSCALE=1` or `0`
(default `auto`).
On WSL it refuses to run unless `ALLOW_WSL=1`, since it installs the profile's whole tool
set and WSL distros are kept to a subset by hand (see **WSL** below).

**After the first boot**, log in once per VM: `claude`, `opencode` (if you use it), `agy`,
and (on personal VMs) `executor login`. Pair T3 Code with each device: `t3 pair --tailscale` (one-time link,
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
(never on `CLAUDE_PROFILE=work`, and skipped when `executor` is left out of `TOOLS`). One
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

**WSL** distros don't run `install.sh`. The repo is cloned (or symlinked) at `~/.dotfiles`,
the files a distro uses are symlinked by hand, and only the tools it needs are installed.
Distro-specific settings go in `~/.zshenv.local`.

- **GitHub:** there's no exe.dev proxy, so `gh` logs in with a fine-grained token per distro,
  limited to the repos that distro needs, and git goes over HTTPS through `gh`.
  `gh auth setup-git` would write to the linked `~/.gitconfig` (this repo), so the helper
  goes in `~/.gitconfig.local`, along with a rewrite that keeps `git@github.com:` remotes
  working:

  ```ini
  [credential "https://github.com"]
      helper =
      helper = !/usr/bin/gh auth git-credential
  [url "https://github.com/"]
      insteadOf = git@github.com:
      insteadOf = ssh://git@github.com/
  ```

- **Headed browsers:** WSLg shows Linux windows on the Windows desktop. `.zshenv` sets
  `DISPLAY` for SSH and T3 sessions, and the chrome-devtools MCP opens its own Chrome there
  (`~/.local/bin/agent-chrome`). Don't point it at a Windows browser's debugging port:
  anything in WSL can reach Windows `localhost`, so that would hand your logged-in browser
  to every process in the distro.

## Layout

```
install.sh              installs tools, then symlinks the two trees below
bootstrap.sh            exe.dev setup script (clone + install.sh)
home/                   mirrored into $HOME          (~/.zshrc, ~/.config/starship.toml, ...)
claude/                 mirrored into ~/.claude       (settings.json, CLAUDE.md)
claude-work/            seed for ~/.claude/settings.json on work VMs (copied, not linked)
agents/skills/          my own skills, mirrored into ~/.agents/skills, ~/.claude/skills and ~/.gemini/config/skills
githooks/               pre-commit guard for this repo (set as core.hooksPath by install.sh)
packages/node-globals.txt   npm globals
packages/go-tools.txt       go install targets
packages/skills.txt         global third-party skill packs (sync-skill-packs) and single skills (skills CLI)
packages/optional-skills.txt curated optional skills picked on demand with `pick-skills`
```

Files are **symlinked**, so editing `~/.zshrc` on a VM edits the repo; commit and push
from there. To add a dotfile, drop it in `home/` at its path relative to `~` and re-run.
Anything a link would overwrite goes to `~/.dotfiles-backup/<timestamp>/`.

Per-machine tweaks that shouldn't be shared go in untracked files:
`~/.zshrc.local`, `~/.zshenv.local`, `~/.gitconfig.local` (e.g. a work email).

A yellow `⚙ N` in the prompt means `~/.dotfiles` has N uncommitted changes, often from a
tool writing to a linked file (e.g. `/model` or `/plugin` editing `settings.json`).

### Profiles: personal vs work

`install.sh` takes `CLAUDE_PROFILE=personal` (default) or `work` and remembers it in
`~/.config/dotfiles/profile`, so plain re-runs keep the VM's profile. The profile picks
the Claude setup and the default tool set.

**Tools.** The shell setup, Node with its core globals, Claude Code, `agy`, the browser
pieces and the dotfiles are always installed. The rest are optional tools, named in `TOOLS`:

| Profile | Default `TOOLS` |
| --- | --- |
| personal | `bun go php rust opencode tmux bat lsd herdr hc turso t3 executor` (all of them) |
| work | `go php bat lsd herdr hc` |

`go` brings gopls, staticcheck and goose; `php` brings Composer, the Laravel installer and
intelephense. Pass `TOOLS="go php bat"` to pick them yourself (`TOOLS=""` for none). The
list is remembered in `~/.config/dotfiles/tools`, so plain re-runs keep it; switching the
profile goes back to the new profile's default. `install.sh` never uninstalls, so leaving a
tool out only stops it from being installed. `executor` is refused on work VMs.

Package lists follow the same choices. A line in `packages/node-globals.txt` or
`packages/skills.txt` that ends in `only:<profile>` or `only:<tool>` applies only to that
profile, or when that tool is in `TOOLS`: `wrangler wrangler only:personal`,
`intelephense intelephense only:php`. That's how work VMs get yarn but not vercel,
wrangler, codex, or the Cloudflare and Vercel skill sets.

**Claude.**

- **personal**: everything in `claude/` is linked, as described above.
- **work**: `claude/` is linked **except** `settings.json` and `CLAUDE.md`.
  `~/.claude/settings.json` is a real file, seeded once from `claude-work/settings.json`
  (TypeScript, Go and PHP LSP plugins), then edited on the VM and never committed. Work
  settings collect org details (auto mode writes internal hosts, secret names and branches
  into them), and this repo is public. There's no user-level `CLAUDE.md`, since work repos
  carry their own. Connectors (Atlassian, Slack, ...) come with the work account login,
  and internal MCPs from each repo's `.mcp.json`. Executor is never installed or wired
  into any agent.

The pre-commit hook rejects staged lines adding an `autoMode` key, plus any regexes (one
per line) in the untracked `~/.config/dotfiles/blocked-patterns`. Put employer-specific
names there instead of in this repo. Bypass a false positive with `git commit --no-verify`.

### Agent skills

Global skills land in `~/.agents/skills` (Codex, opencode) and are symlinked into
`~/.claude/skills` (Claude Code, Grok Build) and `~/.gemini/config/skills` (Antigravity CLI,
plus T3 Code's isolated Antigravity via its `config/skills` symlink).

- **Prefixed global packs** (`prefix:<pfx>` lines in `packages/skills.txt`, e.g.
  `mattpocock/skills prefix:mp- plugin` and `emilkowalski/skills prefix:ek- only:personal`)
  are synced by `sync-skill-packs`: it clones each pack, prefixes folder names and
  `SKILL.md` frontmatter `name`, rewrites intra-pack sibling references (so packs that both
  ship a `prototype` skill don't collide and their cross-references keep working), and
  tracks installed skills in `~/.agents/.skill-packs.json`.
  - Update: `sync-skill-packs` (or `sync-skill-packs --diff` to inspect every rewritten line
    before updating; `--pack mp` for one pack). `install.sh` runs `sync-skill-packs --ensure`
    so re-runs skip already-installed packs and only repair missing symlinks.
- **Plain global skills** (non-`prefix:` lines in `packages/skills.txt`, e.g.
  `anthropics/skills frontend-design`) are installed by `install.sh` with the
  [skills CLI](https://github.com/vercel-labs/skills) (`-a claude-code codex antigravity-cli`).
  A line is either a whole repo, one skill (`owner/repo skill`), or one skill renamed
  (`owner/repo skill new-name`), optionally ending in an `only:` tag (see **Profiles**).
  - Update: `skills update -g` (`skills check -g` to see what's behind).
  - Remove: delete the line and run `skills remove -g <name>`; `install.sh` never uninstalls.
- **Optional per-project / per-VM skills** live in `packages/optional-skills.txt`
  (Cloudflare, Vercel, `agent-browser`, etc.). Run `pick-skills` in a project directory to
  `fzf`-select what you need and hand off to `skills add` (project-local by default into
  `./.agents/skills` and `./.claude/skills`; pass `-g` for global on a single-project VM,
  or `--all` to install every skill in selected `*` packs without prompting).
- **My own skills** go in `agents/skills/<name>/SKILL.md` and are symlinked like the other
  dotfiles, so editing them on a VM edits the repo. Re-run `install.sh` after adding one.

## Notes

- **PATH lives in `.zshenv`, not `.zshrc`**, so non-interactive commands
  (`ssh vm 'pnpm build'`, agents) see the same tools as your terminal.
- **fnm vs Volta:** fnm installs globals per Node version. To keep the Volta feel,
  npm's global prefix is set to `~/.local/share/npm-global`, so global CLIs survive
  switching versions. Change the default with `fnm default <v>`.
- **Package age:** npm is set to `min-release-age=1`, so it only installs versions published
  at least a day ago; current pnpm does the same by default (`minimumReleaseAge`). Most
  malicious releases are pulled within hours. For something released today, override once:
  `npm install --min-release-age=0 <pkg>`.
- **Turning a plugin off on one VM** (e.g. rust-analyzer-lsp on a personal VM without
  `rust`): do it at project scope, in the repo's `.claude/settings.local.json`:
  `{"enabledPlugins": {"rust-analyzer-lsp@claude-plugins-official": false}}`.
  Disabling at user scope would edit the symlinked `settings.json` in this repo. (Work VMs
  can just edit `~/.claude/settings.json`, which isn't linked.)
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
