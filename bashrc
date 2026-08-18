# .bashrc (common, shared across machines)


# 4. Strict local diagnostic flush for locks and rendering caches
#alias fix-anti='pkill -f Antigravity; pkill -f agy; rm -f ~/.config/Antigravity/SingletonLock; rm -rf ~/.config/Antigravity/GPUCache ~/.config/Antigravity/Cache; antigravity'

# Git Prompt and Helpers
set_git_prompt() {
    local lines
    # Query git once for both branch name and status counts
    mapfile -t lines < <(git status --porcelain -b 2>/dev/null)
    
    # If array is empty, we are not in a git repo
    if [ ${#lines[@]} -eq 0 ]; then
        return
    fi
    
    # Extract branch from the header line (e.g. ## main...origin/main)
    local first_line="${lines[0]}"
    local branch="${first_line#"## "}"
    branch="${branch%%...*}"
    
    # Handle initial commit or detached HEAD
    if [[ "$branch" == "HEAD (no branch)" ]]; then
        return
    fi
    if [[ "$branch" == "No commits yet on "* ]]; then
        branch="${branch#No commits yet on }"
    fi

    if [ "$branch" = "main" ]; then
        echo -ne "\033[41;37m[MAIN]\033[0m"
    else
        echo -ne "\033[32m[$branch]\033[0m"
    fi
    
    # Calculate change count (total lines minus the header line)
    local changes=$((${#lines[@]} - 1))
    if [ "$changes" -gt 0 ]; then
        echo -ne "\033[33m*$changes\033[0m"
    fi
}

# Prompt and welcome
if [[ $- == *i* ]]; then
    export PS1="\[\033[34m\]\w\[\033[0m\] \$(set_git_prompt)\n$ "
    echo "Welcome!  Config: ${BASH_SOURCE[0]}"
fi

# Aliases - Podman Containers
alias p='podman'
alias pb='podman build -t'
alias pc='podman compose'
alias pd='podman compose down'
alias pu='podman compose up'
alias prm='podman rm -afv'
alias pprune='podman rm -fv $(podman ps -aq) || echo "Nothing to remove"; podman system prune -f'
alias docker='podman'

# General Aliases
alias repos='cd ~/Repos'
alias ocpc='oc delete po --field-selector=status.phase==Succeeded'
alias gprune='git switch main && git pull --ff-only --no-tags && git fetch --prune --no-tags && git branch -vv | grep ": gone]" | grep -v "^+" | awk "{sub(/^[+* ]+/, \"\"); print \$1}" | xargs -r git branch -D && git branch -a'
alias gpu='git push -u origin $(git branch --show-current)'
alias grm='git fetch origin main && git pull origin main --rebase'
alias gbc='git branch --merged | grep -v "\*" | xargs -n 1 git branch -d'
alias gd='git diff'
alias gs='git status'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias c='code'

# agy CLI — resolve from PATH first, fall back to well-known install dir
alias agy='_agy_run() { if command -v agy &>/dev/null; then command agy "$@"; else "${HOME}/.local/bin/agy" "$@"; fi; }; _agy_run'
# Antigravity hub — resolve from PATH first, fall back to well-known install dir
alias a='_anti_run() { if command -v antigravity &>/dev/null; then command antigravity "$@"; else "${HOME}/.local/bin/antigravity/antigravity" "$@"; fi; }; _anti_run'


# Fixes
alias fix-wifi="sudo systemctl stop NetworkManager && sudo modprobe -r ath11k_pci && sudo modprobe ath11k_pci && sudo systemctl start NetworkManager"

# Functions
## Git Add and Commit
ga () {
    if [ -n "$1" ]; then
        git add -A
        git commit -m "$*"
    else
        echo "Git Add => Please provide a commit message"
        return 1
    fi
}

## Git Add, Commit, and Push
gap () {
    ga "$@" && (git push || git push -u origin $(git branch --show-current))
}

## Podman build and up with cleanup on interrupt
pub() {
    cleanup() {
        echo -e "\nInterrupted: Cleaning up..."
        podman compose down${REMOVE_VOLUMES:+" -v"}
    }
    trap cleanup INT
    podman compose up --build
}

# Fix Antigravity Terminal Blindness
if [[ -n "$ANTIGRAVITY_AGENT" ]]; then
    export PS1='$ '
    unset PROMPT_COMMAND
    unset GITHUB_TOKEN
    unset GH_TOKEN
    return
fi

# History settings for better usability
export HISTCONTROL=ignoredups:erasedups
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s histappend

# Set default editor
export EDITOR=nano

# Standard alias for quick AI piping
alias ai='gemini -p'

# Helper function to pipe logs directly
function ailog() {
    cat "$1" | gemini -p "Analyze these logs and find the root cause."
}

# Lower Compose verbosity
export PODMAN_COMPOSE_WARNING_LOGS=false

# ── Quality of Life ────────────────────────────────────────────────────────
alias ll="ls -alF"
alias la="ls -A"
alias l="ls -CF"
alias ..="cd .."
alias ...="cd ../.."
alias docker-compose="podman-compose"



# ── NVM ────────────────────────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
