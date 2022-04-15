{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: {
      devShell = import ./. {
        nixpkgs = nixpkgs.legacyPackages.${system};
        nixpkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
      };
    });
}
