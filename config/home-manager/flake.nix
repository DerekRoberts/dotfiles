{
  description = "Derek's Home-Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs   = nixpkgs.legacyPackages.${system};
      mkHome = profile: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ./home.nix
          { _module.args.profile = profile; }
        ];
      };
    in {
      # Apply with:
      #   home-manager switch --flake .#dev
      #   home-manager switch --flake .#desktop
      homeConfigurations.dev     = mkHome "dev";
      homeConfigurations.desktop = mkHome "desktop";
    };
}
