{ flake-parts-lib, lib, ... }:
{
  options = {
    perSystem = flake-parts-lib.mkPerSystemOption ({ config, pkgs, system, ... }: {
      options.ghc-nix-shells = lib.mkOption {
        description = ''
          `ghc.nix` are nix expressions that enable you to quickly get started with GHC development
        '';
        type = with lib.types; lazyAttrsOf (submoduleWith {
          modules = import ./modules.nix { inherit pkgs lib system; };
        });
        # TODO: add a sensible default configuration
        default = { };
      };
      config.devShells = lib.mapAttrs (_name: shell: shell.settings.shell) config.ghc-nix-shells;
    });
  };
}
