# Derek's Dotfiles

Personal system configurations, aliases, prompts, and tool settings for Fedora (Workstation and Kinoite) and KDE Plasma.

## Structure

```
├── README.md
├── setup.sh            # Bootstrap installation script
├── bashrc              # Clean shell aliases, functions, and optimized git prompt
├── gitconfig           # Global git configurations (aliases, rebase defaults)
├── bin/
│   └── updown          # System updates and shutdown orchestration script
└── config/
    ├── antigravity/    # Antigravity desktop assistant instructions and launch flags
    └── vscode/         # VS Code user settings
```

## Setup Instructions

Clone this repository to `~/Repos/dotfiles` and execute the bootstrap script:

```bash
cd ~/Repos
git clone git@github.com:DerekRoberts/dotfiles.git
cd dotfiles
./setup.sh
```

Restart your terminal or run `source ~/.bashrc` to load changes.

## Potential Next Steps (To brainstorm in GitHub Issues)

- [ ] **Fedora/Kinoite Post-Install Playbooks**: Automated flatpak and rpm-ostree package provisioning.
- [ ] **KDE Shortcuts Exporter/Importer**: Quick restoration of Plasma global keyboard configurations.
