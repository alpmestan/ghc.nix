{
  description = "ghc.nix - the ghc devShell";
  nixConfig = {
    bash-prompt = "\\[\\e[34;1m\\]ghc.nix ~ \\[\\e[0m\\]";
    extra-substituters = [ "https://ghc-nix.cachix.org" ];
    extra-trusted-public-keys = [ "ghc-nix.cachix.org-1:wI8l3tirheIpjRnr2OZh6YXXNdK2fVQeOI4SVz/X8nA=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
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

  outputs = { nixpkgs, all-cabal-hashes, pre-commit-hooks, ghc-wasm-meta, ... }: with nixpkgs.lib; let
    supportedSystems =
      # allow nix flake show and nix flake check when passing --impure
      if builtins.hasAttr "currentSystem" builtins
      then [ builtins.currentSystem ]
      else nixpkgs.lib.systems.flakeExposed;
    perSystem = genAttrs supportedSystems;

    lib = { inherit supportedSystems perSystem; };

    defaultSettings = system: {
      inherit nixpkgs system;
      all-cabal-hashes = all-cabal-hashes.outPath;
      inherit (ghc-wasm-meta.outputs.packages."${system}") wasi-sdk wasmtime;
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
  rec {
    devShells = perSystem (system: rec {
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

      formatting = nixpkgs.legacyPackages.${system}.mkShell {
        inherit (pre-commit-check system) shellHook;
      };
    });

    checks = perSystem (system: {
      formatting = pre-commit-check system;
      ghc-nix-shell = devShells.${system}.ghc-nix;
    });

    # NOTE: this attribute is used by the flake-compat code to allow passing arguments to ./ghc.nix
    legacy = args: import ./ghc.nix (defaultSettings args.system // args);

    templates.default = {
      path = ./template;
      description = "Quickly apply settings from flakes";
      welcomeText = ''
        Welcome to ghc.nix!
        Set your settings in the `userSettings` attributeset in the `flake.nix`.
        Learn more about available arguments at https://github.com/alpmestan/ghc.nix/
      '';
    };

    inherit lib;
  };
}
