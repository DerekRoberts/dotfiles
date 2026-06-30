#!/bin/bash
set -euo pipefail

GITIGNORE_URL="https://raw.githubusercontent.com/bcgov/quickstart-openshift/main/.gitignore"
GLOBAL_GITIGNORE="$HOME/.gitignore_global"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
  echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
  echo -e "${YELLOW}ℹ $1${NC}"
}

print_skip() {
  echo -e "${YELLOW}→ $1${NC}"
}

# Helper function to read user input safely (handles piped installation correctly)
# shellcheck disable=SC2034
read_input() {
  local prompt="$1"
  local -n ref="$2"
  if [ -t 0 ]; then
    read -r -p "$prompt" ref || true
  elif [ -c /dev/tty ] && { true </dev/tty; } 2>/dev/null; then
    read -r -p "$prompt" ref < /dev/tty || true
  else
    read -r -p "$prompt" ref < /dev/null || true
  fi
}

# Function to set git config only if not already set
set_git_config() {
  local key="$1"
  local value="$2"
  local scope="${3:-global}"
  
  local current_value
  current_value=$(command git config --"$scope" --get "$key" 2>/dev/null || true)
  
  if [[ -z "$current_value" ]]; then
    command git config --"$scope" "$key" "$value"
    print_success "Set $key = $value"
  else
    print_skip "Skipping $key (already set to: $current_value)"
  fi
}

# Configure user name and email
configure_user() {
  print_header "Git User Configuration"
  
  local name=""
  local email=""
  local current_name
  local current_email
  current_name=$(command git config --global --get user.name 2>/dev/null || true)
  current_email=$(command git config --global --get user.email 2>/dev/null || true)
  
  if [[ -z "$current_name" ]]; then
    read_input "What is your name? " name
    if [[ -n "$name" ]]; then
      command git config --global user.name "$name"
      print_success "Set user.name = $name"
    fi
  else
    print_skip "user.name already set to: $current_name"
  fi
  
  if [[ -z "$current_email" ]]; then
    read_input "What is your email address? " email
    if [[ -n "$email" ]]; then
      command git config --global user.email "$email"
      print_success "Set user.email = $email"
    fi
  else
    print_skip "user.email already set to: $current_email"
  fi
}

# Set up global gitignore
configure_gitignore() {
  print_header "Global .gitignore Configuration"
  
  local choice=""
  local current_gitignore
  current_gitignore=$(command git config --global --get core.excludesfile 2>/dev/null || true)
  
  local temp_file
  temp_file=$(mktemp "${TMPDIR:-/tmp}/git-setup-gitignore.XXXXXXXXXX")
  trap 'rm -f "$temp_file"' EXIT
  
  print_info "Downloading recommended gitignore patterns..."
  if ! curl -fsSL "$GITIGNORE_URL" -o "$temp_file"; then
    print_info "Failed to download gitignore patterns, skipping gitignore configuration"
    return 0
  fi
  
  if [[ -n "$current_gitignore" ]] && [[ -f "$current_gitignore" ]]; then
    print_skip "core.excludesfile already set to: $current_gitignore"
    
    if cmp -s "$current_gitignore" "$temp_file"; then
      print_skip "Existing gitignore matches recommended patterns, skipping setup"
      return 0
    fi
    
    echo "File exists and differs from recommended patterns. How would you like to proceed?"
    echo "  1) Replace - overwrite with recommended patterns"
    echo "  2) Append - add recommended patterns to existing file"
    echo "  3) Skip - keep current file unchanged"
    read_input "Choose [1/2/3] (default: 3): " choice
    
    case "${choice}" in
      1)
        if cp "$temp_file" "$current_gitignore"; then
          print_success "Replaced $current_gitignore with recommended patterns"
        else
          print_info "Failed to replace gitignore patterns"
        fi
        ;;
      2)
        if {
          echo ""
          echo "# Patterns from bcgov/quickstart-openshift"
          cat "$temp_file"
        } >> "$current_gitignore"; then
          print_success "Appended recommended patterns to $current_gitignore"
        else
          print_info "Failed to append patterns to $current_gitignore"
        fi
        ;;
      *)
        print_skip "Keeping existing gitignore unchanged"
        ;;
    esac
  else
    if cp "$temp_file" "$GLOBAL_GITIGNORE"; then
      command git config --global core.excludesfile "$GLOBAL_GITIGNORE"
      print_success "Set core.excludesfile = $GLOBAL_GITIGNORE"
    else
      print_info "Failed to save global gitignore"
    fi
  fi
  
  rm -f "$temp_file"
  trap - EXIT
}

# Apply recommended git configurations
configure_git_settings() {
  print_header "Recommended Git Configuration"
  print_info "Applying settings from Git core developers' recommendations"
  
  # Basic branch settings
  set_git_config "init.defaultBranch" "main"
  set_git_config "branch.sort" "-committerdate"
  set_git_config "tag.sort" "version:refname"
  
  # Diff settings
  set_git_config "diff.algorithm" "histogram"
  set_git_config "diff.colorMoved" "plain"
  set_git_config "diff.mnemonicPrefix" "true"
  set_git_config "diff.renames" "true"
  
  # Push settings
  set_git_config "push.default" "simple"
  set_git_config "push.autoSetupRemote" "true"
  set_git_config "push.followTags" "true"
  
  # Fetch settings
  set_git_config "fetch.prune" "true"
  set_git_config "fetch.pruneTags" "true"
  
  # Rebase settings
  set_git_config "rebase.autoSquash" "true"
  set_git_config "rebase.autoStash" "true"
  set_git_config "rebase.updateRefs" "true"
  
  # Commit settings
  set_git_config "commit.verbose" "true"
  
  # Rerere (reuse recorded resolution)
  set_git_config "rerere.enabled" "true"
  set_git_config "rerere.autoupdate" "true"
  
  # Help settings
  set_git_config "help.autocorrect" "prompt"
  
  # Column display
  set_git_config "column.ui" "auto"
  
  # Grep settings
  set_git_config "grep.patternType" "perl"
}

# Configure signed commits using SSH keys
configure_commit_signing() {
  print_header "Signed Commits Configuration"
  
  # Check if signing is already configured
  local current_sign
  current_sign=$(command git config --global --get commit.gpgsign 2>/dev/null || true)
  local current_key
  current_key=$(command git config --global --get user.signingkey 2>/dev/null || true)
  
  if [[ "$current_sign" == "true" ]] && [[ -n "$current_key" ]]; then
    print_skip "Commit signing already configured (key: $current_key)"
    return 0
  fi
  
  local choice=""
  read_input "Do you want to enable SSH commit signing? [y/N]: " choice
  if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    print_skip "Keeping unsigned commits"
    return 0
  fi
  
  local key_path=""
  local scan_choice=""
  read_input "Would you like the script to scan ~/.ssh/ for public keys? [y/N]: " scan_choice
  
  if [[ "$scan_choice" == "y" || "$scan_choice" == "Y" ]]; then
    local ssh_dir="$HOME/.ssh"
    if [[ -d "$ssh_dir" ]]; then
      local expected_names=(
        "id_ed25519.pub"
        "id_rsa.pub"
        "id_ecdsa.pub"
        "id_dsa.pub"
        "id_ed25519_sk.pub"
        "id_ecdsa_sk.pub"
      )
      local pub_keys=()
      local name
      for name in "${expected_names[@]}"; do
        local key_file="$ssh_dir/$name"
        if [[ -f "$key_file" ]]; then
          pub_keys+=("$key_file")
        fi
      done
      
      if [[ ${#pub_keys[@]} -gt 0 ]]; then
        echo "Discovered public keys:"
        local idx=1
        local key
        for key in "${pub_keys[@]}"; do
          echo "  $idx) $(basename "$key")"
          ((idx++))
        done
        echo "  $idx) Enter path manually"
        
        local selection=""
        read_input "Choose a key [1-$idx]: " selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#pub_keys[@]} ]]; then
          local selected_pub="${pub_keys[$((selection - 1))]}"
          # shellcheck disable=SC2088
          key_path="~/.ssh/$(basename "$selected_pub")"
        fi
      else
        print_info "No expected public keys found in ~/.ssh/"
      fi
    else
      print_info "Directory ~/.ssh/ does not exist."
    fi
  fi
  
  # Fallback to manual entry if not chosen during scan
  if [[ -z "$key_path" ]]; then
    read_input "Enter the path to your public SSH key (e.g., ~/.ssh/id_ed25519.pub): " key_path
    if [[ -z "$key_path" ]]; then
      print_skip "No key path provided. Skipping signing configuration."
      return 0
    fi
  fi
  
  local expanded_path
  expanded_path="${key_path/#\~/$HOME}"
  if [[ ! -f "$expanded_path" ]]; then
    print_info "Warning: File not found at $key_path"
  fi
  
  command git config --global commit.gpgsign true
  command git config --global gpg.format ssh
  command git config --global user.signingkey "$key_path"
  print_success "Commit signing configured using key: $key_path"
}

# Main execution
main() {
  echo -e "${BLUE}=== Git Configuration Setup ===${NC}"
  echo -e "${BLUE}bcgov/agent-guardrails${NC}"
  
  configure_user
  configure_gitignore
  configure_git_settings
  configure_commit_signing
  
  print_header "Setup Complete!"
  echo -e "${GREEN}Your Git configuration has been updated with recommended settings.${NC}"
  echo -e "${YELLOW}Run 'git config --global --list' to see all your global settings.${NC}"
  echo ""
}

main
