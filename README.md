# Derek's Dotfiles

Personal machine config: shell, git, personal-instruction sync (from GitHub main), and tool symlinks.

See **[docs/ai-architecture.md](docs/ai-architecture.md)** for how this fits the wider AI stack.

## Quick start

**Fresh machine (curl bootstrap):**

```bash
curl -fsSL https://raw.githubusercontent.com/DerekRoberts/dotfiles/main/setup.sh | bash
source ~/.bashrc
```

**Already cloned:**

```bash
~/Repos/dotfiles/setup.sh
source ~/.bashrc
```

`setup.sh` clones or updates the repo, wires local configs from the clone, then syncs the **personal** instructions block from GitHub `main` into your global prompt hub. Work standards in the hub come from org Copilot / VS Code — dotfiles does not manage those.

Guardrails are separate — install once via the wrapper (downloads to a temp file before executing):

```bash
~/Repos/dotfiles/scripts/install-guardrails.sh
# or clone bcgov/agent-guardrails and run ~/Repos/agent-guardrails/setup.sh
```

## AI layout (summary)

| Component | Location |
|-----------|----------|
| Work standards | `~/.config/Code/User/prompts/global.instructions.md` (org Copilot / VS Code) |
| Personal instructions (canonical) | GitHub `main` → `config/ai/personal.instructions.md` |
| Personal block in hub | Delimited section synced by `bundle-ai-instructions.sh` |
| Guardrails | [bcgov/agent-guardrails](https://github.com/bcgov/agent-guardrails) via `scripts/install-guardrails.sh` |
| Prompt recipes (optional) | `docs/agent-prompt-card.md` |

Tools symlinked to the hub: **VS Code Copilot**, **Cursor**, **Antigravity**.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DOTFILES_DIR` | `~/Repos/dotfiles` | Clone location |
| `DOTFILES_REPO` | `https://github.com/DerekRoberts/dotfiles.git` | Clone URL |
| `DOTFILES_BRANCH` | `main` | Branch to clone/pull |
| `DOTFILES_SKIP_PULL` | *(unset)* | Set to skip `git pull` |
| `PERSONAL_INSTRUCTIONS_URL` | raw GitHub `main` URL | Override for local dev only |
| `GLOBAL_INSTRUCTIONS_OUTPUT` | `~/.config/Code/User/prompts/global.instructions.md` | Prompt hub path |

## Structure

```
├── setup.sh                        # clone/pull + wire + sync
├── bashrc
├── gitconfig
├── bin/updown
├── scripts/
│   ├── bundle-ai-instructions.sh   # fetch personal from GitHub → hub
│   └── install-guardrails.sh       # thin wrapper → agent-guardrails
├── config/
│   ├── ai/personal.instructions.md # canonical source (on main)
│   ├── antigravity/
│   └── vscode/
└── docs/
    ├── ai-architecture.md
    └── agent-prompt-card.md
```
