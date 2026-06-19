# Derek's Dotfiles

Personal machine config: shell, git, AI personal-instruction sync, guardrails wrapper, and tool symlinks.

See **[docs/ai-architecture.md](docs/ai-architecture.md)** for the full four-repo AI stack map.

## Quick start

```bash
# Requires ~/Repos/agent-guardrails cloned (work standards live in global hub already)
cd ~/Repos/dotfiles && ./setup.sh
source ~/.bashrc
```

## AI layout (summary)

| Component | Location |
|-----------|----------|
| Work standards | `~/.config/Code/User/prompts/global.instructions.md` (org Copilot / VS Code) |
| Personal instructions source | `config/ai/personal.instructions.md` |
| Personal block in hub | Delimited section synced by `bundle-ai-instructions.sh` |
| Guardrails source | `~/Repos/agent-guardrails/` (via `scripts/install-guardrails.sh`) |
| Skills catalogue | `npx skills add bcgov/agent-skills` → `~/.agents/skills/` |
| Prompt recipes (optional) | `docs/agent-prompt-card.md` |

Tools symlinked to the hub: **VS Code Copilot**, **Cursor**, **Antigravity**.

## Structure

```
├── setup.sh
├── bashrc
├── gitconfig
├── bin/updown
├── scripts/
│   ├── bundle-ai-instructions.sh   # sync personal block → global hub
│   └── install-guardrails.sh       # thin wrapper → agent-guardrails
├── config/
│   ├── ai/personal.instructions.md
│   ├── antigravity/
│   └── vscode/
└── docs/
    ├── ai-architecture.md
    └── agent-prompt-card.md
```
