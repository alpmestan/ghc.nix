{
  description = "flake-parts x ghc.nix";

  nixConfig = {
    bash-prompt = "\\[\\e[34;1m\\]ghc.nix ~ \\[\\e[0m\\]";
    extra-substituters = [ "https://ghc-nix.cachix.org" ];
    extra-trusted-public-keys = [ "ghc-nix.cachix.org-1:wI8l3tirheIpjRnr2OZh6YXXNdK2fVQeOI4SVz/X8nA=" ];
  };

  inputs = {
    ghc-nix.url = "github:alpmesta/ghx.nix";
    parts.follows = "ghc-nix/parts";
    nixpkgs.follows = "ghc-nix/nixpkgs";
    all-cabal-hashes.follows = "ghc-nix/all-cabal-hashes";
    wasm-meta.follows = "ghc-nix/ghc-wasm-meta";
  };

  outputs = inputs:
    inputs.parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.ghc-nix.flakeModule ];
      systems = [ "x86_64-linux" ];
      perSystem = { system, ... }: {
        ghc-nix-shells = {
          default.settings = {
            inherit (inputs) nixpkgs all-cabal-hashes;
          };
          js.settings = {
            inherit (inputs) nixpkgs all-cabal-hashes;
            crossTarget = "javascript-unknown-ghcjs";
            EMSDK.enable = true;
            dwarf.enable = false;
          };
          wasm.settings = {
            inherit (inputs) nixpkgs all-cabal-hashes;
            wasi-sdk.package = inputs.wasm-meta.packages.${system}.wasi-sdk;
            wasmtime.package = inputs.wasm-meta.packages.${system}.wasmtime;
            wasm.enable = true;
          };
        };
      };
    };
}
