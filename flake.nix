{
  description = "ghc.nix flake";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.05";
    # NOTE: matches nixpkgs-unstable from sources.nix
    # This is needed until the bootGHC version upgrades to a version that 
    # nixpkgs-unstable contains an hls for 
    nixpkgs-unstable.url = "github:nixos/nixpkgs/e14f9fb57315f0d4abde222364f19f88c77d2b79";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable }: with nixpkgs.lib; let
    supportedSystems = nixpkgs.lib.systems.flakeExposed;
    perSystem = genAttrs supportedSystems;

    pkgsFor = system: import nixpkgs { inherit system; };
    unstablePkgsFor = system: import nixpkgs-unstable { inherit system; };
  in
  {
    devShells = perSystem (system: {
      default = import ./. {
        inherit system;
        withHadrianDeps = true;
        withIde = true;
        nixpkgs = pkgsFor system;
        nixpkgs-unstable = unstablePkgsFor system;
      };
    });
    formatter = perSystem (system:
      let
        pkgs = pkgsFor system;
      in
      pkgs.nixpkgs-fmt);
  };
}
