{
  description = "ghc.nix - the ghc devShell";
  nixConfig = {
    bash-prompt = "\\[\\e[34;1m\\]ghc.nix ~ \\[\\e[0m\\]";
    extra-substituters = [ "https://ghc-nix.cachix.org" ];
    extra-trusted-public-keys = [ "ghc-nix.cachix.org-1:wI8l3tirheIpjRnr2OZh6YXXNdK2fVQeOI4SVz/X8nA=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    all-cabal-hashes = {
      url = "github:commercialhaskell/all-cabal-hashes/hackage";
      flake = false;
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.nixpkgs-stable.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, all-cabal-hashes, pre-commit-hooks, ... }: with nixpkgs.lib; let
    supportedSystems =
      # allow nix flake show and nix flake check when passing --impure
      if builtins.hasAttr "currentSystem" builtins
      then [ builtins.currentSystem ]
      else nixpkgs.lib.systems.flakeExposed;
    perSystem = genAttrs supportedSystems;

    defaultSettings = system: {
      inherit nixpkgs nixpkgs-unstable system;
      all-cabal-hashes = all-cabal-hashes.outPath;
    };

    pre-commit-check = system: pre-commit-hooks.lib.${system}.run {
      src = ./.;
      hooks = {
        nixpkgs-fmt.enable = true;
        statix.enable = true;
        deadnix.enable = true;
        typos.enable = true;
      };
    };

    # NOTE: change this according to the settings allowed in the ./ghc.nix file and described 
    # in the `README.md`
    userSettings = {
      withHadrianDeps = true;
      withIde = true;
    };
  in
  {
    devShells = perSystem (system: rec {
      ghc-nix = import ./ghc.nix (defaultSettings system // userSettings);
      default = ghc-nix;

      formatting = nixpkgs.legacyPackages.${system}.mkShell {
        inherit (pre-commit-check system) shellHook;
      };
    });

    checks = perSystem (system: { formatting = pre-commit-check system; });

    # NOTE: this attribute is used by the flake-compat code to allow passing arguments to ./ghc.nix
    legacy = args: import ./ghc.nix (defaultSettings args.system // args);
  };
}
