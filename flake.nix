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
    devshell.url = "github:numtide/devshell";
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
    inputs.parts.lib.mkFlake { inherit inputs; } {
      systems =
        # allow nix flake show and nix flake check when passing --impure
        if builtins.hasAttr "currentSystem" builtins
        then [ builtins.currentSystem ]
        else inputs.nixpkgs.lib.systems.flakeExposed;
      imports = [
        (import ./modules/flake-module.nix)
        inputs.pre-commit-hooks.flakeModule
        inputs.devshell.flakeModule
      ];
      perSystem = { config, system, lib, pkgs, ... }: {
        pre-commit = {
          check.enable = true;
          settings.hooks = {
            nixpkgs-fmt.enable = true;
            statix.enable = true;
            deadnix.enable = true;
            typos.enable = true;
          };
        };
        ghc-nix-shells = rec {
          ghc-nix.settings = {
            inherit (inputs) nixpkgs all-cabal-hashes;
          };
          default = ghc-nix;
          js-cross.settings = {
            inherit (inputs) nixpkgs all-cabal-hashes;
            crossTarget = "javascript-unknown-ghcjs";
            EMSDK.enable = true;
            dwarf.enable = false;
          };
          wasm-cross.settings = {
            inherit (inputs) nixpkgs all-cabal-hashes;
            wasi-sdk.package = inputs.ghc-wasm-meta.packages.${system}.wasi-sdk;
            wasmtime.package = inputs.ghc-wasm-meta.packages.${system}.wasmtime;
            wasm.enable = true;
          };
          # Backward compat synonym
          wasi-cross = wasm-cross;
        };

        devshells = {
          formatting = {
            devshell.startup.pre-commit-hooks.text = config.pre-commit.installationScript;
            commands = [
              {
                name = "format";
                help = "format all files";
                command = "pre-commit run --all-files";
              }
            ];
          };
        };
        checks = {
          ghc-nix-shell = config.devShells.ghc-nix;
        };

        packages.moduleDocs =
          let
            eval = lib.evalModules { modules = import ./modules/modules.nix { inherit pkgs system lib; }; };
            moduleDocs = (pkgs.nixosOptionsDoc { inherit (eval) options; }).optionsCommonMark;
            summary = pkgs.writeTextFile {
              name = "SUMMARY.md";
              text = ''
                # `ghc.nix` documentation

                - [getting started](./README.md)
                - [module options](./module-docs.md)
              '';
            };
            booktoml = pkgs.writeTextFile {
              name = "book.toml";
              text = ''
                [book]
                authors = ["The GHC.nix contributors"]
                title = "GHC.nix documentation"
                language = "en"
                multilingual = false
                src = "src"
              '';
            };
          in
          pkgs.runCommand "mdbook"
            {
              nativeBuildInputs = [
                pkgs.mdbook
              ];
            } ''
            mkdir -p src
            cp ${booktoml} ./book.toml
            cp ${summary} ./src/SUMMARY.md
            cat ${./README.md} > ./src/README.md
            cat ${moduleDocs} > ./src/module-docs.md
            ls src
            mdbook build
            mv book $out
          '';
      };
      flake = _: {
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
        # NOTE: this attribute is used by the flake-compat code to allow passing arguments to ./ghc.nix
        legacy =
          let
            defaultSettings = system: {
              inherit system;
              inherit (inputs) nixpkgs;
              inherit (inputs.ghc-wasm-meta.outputs.packages."${system}") wasi-sdk wasmtime;
              all-cabal-hashes = inputs.all-cabal-hashes.outPath;
            };
          in
          args: import ./ghc.nix (defaultSettings args.system // args);
      };
    };
}
