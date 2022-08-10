# Setup instructions:
# 1. Go to your local GHC directory
# 2. Add a shell.nix file with this code:
#   (import
#     (
#       let lock = builtins.fromJSON (builtins.readFile <path/to/ghc.nix>/flake.lock); in
#       fetchTarball {
#         url = "https://github.com/edolstra/flake-compat/archive/${lock.nodes.flake-compat.locked.rev}.tar.gz";
#         sha256 = lock.nodes.flake-compat.locked.narHash;
#       }
#     )
#     { src = <path-to-ghc.nix>/.; }
#   ).shellNix
#
# 3. Notice that this calls the shellNix attritbute. shellNix corresponds to the
#    default devShell at the end of this file. Change this shell as needed or
#    change the default package in this file and change .shellNix to .defaultNix
#
# Usage examples:
#   nix-shell path/to/ghc.nix/ --pure --run './boot && ./configure && make -j4'
#   nix-shell path/to/ghc.nix/        --run 'hadrian/build -c -j4 --flavour=quickest'
#   nix-shell path/to/ghc.nix/        --run 'THREADS=4 ./validate --slow'
{
  description = "GHC build environment flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    cabal-hashes = { url   = "github:commercialhaskell/all-cabal-hashes/hackage";
                     flake = false;
                   };

    pkgs.url          = "nixpkgs/nixos-22.05";
    pkgs-unstable.url = "nixpkgs/nixos-unstable";
  };

  outputs = { self
            , pkgs
            , pkgs-unstable
            , flake-utils
            , flake-compat
            , cabal-hashes
            }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
            nixpkgs-unstable = pkgs-unstable.legacyPackages.${system};
            nixpkgs          = pkgs.legacyPackages.${system};

        in rec
          { packages = { default = import ./default.nix { withIde         = true;
                                                          withHadrianDeps = true;
                                                          withDocs        = true;
                                                          withLlvm        = true;
                                                          withEMSDK       = false;
                                                          inherit cabal-hashes;
                                                          inherit nixpkgs;
                                                          inherit nixpkgs-unstable;
                                                        };


                       };

            # Unfortunately flake-compat (the utility library for flakes to be
            # compatible with legacy nix commands) has a limitation where the
            # legacy commands only allows us to build an environment for either
            # the default package (shown above in packages.default) or the
            # default shell (shown below).
            devShells = { default = import ./default.nix { withIde         = true;
                                                           withHadrianDeps = true;
                                                           withDocs        = true;
                                                           withLlvm        = true;
                                                           withEMSDK       = false;
                                                           inherit cabal-hashes;
                                                           inherit nixpkgs;
                                                           inherit nixpkgs-unstable;
                                                         };

                          # your-special-shell-here = import ./default.nix { withIde         = true;
                          #                                                  withHadrianDeps = true;
                          #                                                  withDocs        = true;
                          #                                                  withLlvm        = true;
                          #                                                  withEMSDK       = false;
                          #                                                  inherit cabal-hashes;
                          #                                                  inherit nixpkgs;
                          #                                                  inherit nixpkgs-unstable;
                          #                                                };
                        };
          }
      );
}
