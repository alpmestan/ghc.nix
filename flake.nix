{
  description = "ghc.nix flake";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/22.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable }: with nixpkgs.lib; let
    supportedSystems = nixpkgs.lib.systems.flakeExposed;
    perSystem = genAttrs supportedSystems;

    pkgsFor = system: import nixpkgs { inherit system; };
    unstablePkgsFor = system: import nixpkgs-unstable { inherit system; };
  in
  {
    devShells = perSystem (system: {
      default = (import ./. { inherit system; }) {
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
