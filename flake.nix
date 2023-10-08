{
  description = "ghc.nix - the ghc devShell";
  nixConfig = {
    bash-prompt = "\\[\\e[34;1m\\]ghc.nix ~ \\[\\e[0m\\]";
    extra-substituters = [ "https://ghc-nix.cachix.org" ];
    extra-trusted-public-keys = [ "ghc-nix.cachix.org-1:wI8l3tirheIpjRnr2OZh6YXXNdK2fVQeOI4SVz/X8nA=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    parts.url = "github:hercules-ci/flake-parts";
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
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";
    };

    ghc-wasm-meta.url = "gitlab:ghc/ghc-wasm-meta?host=gitlab.haskell.org";
  };

  outputs = inputs:
    let
      defaultSettings = system: {
        inherit system;
        inherit (inputs) nixpkgs;
        inherit (inputs.ghc-wasm-meta.outputs.packages."${system}") wasi-sdk wasmtime;
        all-cabal-hashes = inputs.all-cabal-hashes.outPath;
      };

      # NOTE: change this according to the settings allowed in the ./ghc.nix file and described
      # in the `README.md`
      userSettings = {
        withHadrianDeps = true;
        withIde = true;
      };
    in
    inputs.parts.lib.mkFlake { inherit inputs; } {
      systems =
        # allow nix flake show and nix flake check when passing --impure
        if builtins.hasAttr "currentSystem" builtins
        then [ builtins.currentSystem ]
        else inputs.nixpkgs.lib.systems.flakeExposed;
      imports = [
        inputs.pre-commit-hooks.flakeModule
      ];
      perSystem = { config, pkgs, system, ... }: {
        pre-commit = {
          check.enable = true;
          settings.hooks = {
            nixpkgs-fmt.enable = true;
            statix.enable = true;
            deadnix.enable = true;
            typos.enable = true;
          };
        };

        devShells = rec {
          default = ghc-nix;
          ghc-nix = import ./ghc.nix (defaultSettings system // userSettings);
          wasm-cross = import ./ghc.nix (defaultSettings system // userSettings // { withWasm = true; });
          # Backward compat synonym
          wasi-cross = wasm-cross;
          js-cross = import ./ghc.nix (defaultSettings system // userSettings // {
            crossTarget = "javascript-unknown-ghcjs";
            withEMSDK = true;
            withDwarf = false;
          });

          formatting = pkgs.mkShell {
            shellHook = config.pre-commit.installationScript;
          };
        };

        checks = {
          ghc-nix-shell = config.devShells.ghc-nix;
        };

      };
      flake = _: {
        # NOTE: this attribute is used by the flake-compat code to allow passing arguments to ./ghc.nix
        legacy = args: import ./ghc.nix (defaultSettings args.system // args);
        flakeModule = import ./modules/flake-module.nix;
        templates = {
          default = {
            path = ./templates/default;
            description = "Quickly apply settings from flakes";
            welcomeText = ''
              Welcome to ghc.nix!
              Set your settings in the `userSettings` attributeset in the `flake.nix`.
              Learn more about available arguments at https://github.com/alpmestan/ghc.nix/
            '';
          };
          modules = {
            path = ./templates/modules;
            description = "Quickly apply settings from flakes using modules";
            welcomeText = ''
              Welcome to ghc.nix!
              Set your settings in the `perSystem` attribute of the `flake.nix`.
              Learn more about available arguments at https://github.com/alpmestan/ghc.nix/
              Learn more about flake parts at https://flake.parts
            '';
          };
        };
      };
    };
}
