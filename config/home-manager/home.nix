{ config, pkgs, lib, profile, ... }:

let
  isDev = profile == "dev";
in {
  # ---------------------------------------------------------------------------
  # Identity — resolved at switch-time from the running user's environment
  # ---------------------------------------------------------------------------
  home.username    = builtins.getEnv "USER";
  home.homeDirectory = builtins.getEnv "HOME";
  home.stateVersion  = "25.05";

  # ---------------------------------------------------------------------------
  # Packages
  # ---------------------------------------------------------------------------
  home.packages = lib.optionals isDev (with pkgs; [
    # VCS & code review
    gh

    # Linters / formatters (replaces bootstrap-tools.sh GitHub binary downloads)
    hadolint
    actionlint
    yq-go

    # Data wrangling
    jq

    # Search & fuzzy-find
    ripgrep
    fzf

    # Node version management (fnm manages runtime versions; per-project .nvmrc)
    fnm

    # Python
    python3
    uv

    # Container tooling
    podman-compose

    # Dynamic linker compatibility for pre-built binaries (Cursor, AppImages)
    nix-ld
  ]);

  # ---------------------------------------------------------------------------
  # gh: use file keyring to prevent KWallet DBus hangs on KDE/Kinoite
  # ---------------------------------------------------------------------------
  programs.gh = lib.mkIf isDev {
    enable = true;
    settings = {
      keyring_backend = "file";
    };
  };

  # ---------------------------------------------------------------------------
  # Bash integration
  # ---------------------------------------------------------------------------
  programs.bash = lib.mkIf isDev {
    enable = true;
    # fnm hook: auto-switches Node version when entering a directory with .nvmrc
    initExtra = ''
      if command -v fnm &>/dev/null; then
        eval "$(fnm env --use-on-cd --shell bash)"
      fi
    '';
  };

  # ---------------------------------------------------------------------------
  # Home-Manager manages itself
  # ---------------------------------------------------------------------------
  programs.home-manager.enable = true;
}
