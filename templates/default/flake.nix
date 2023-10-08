{
  description = "adhoc ghc.nix devShell flake";
  nixConfig = {
    bash-prompt = "\\[\\e[34;1m\\]ghc.nix ~ \\[\\e[0m\\]";
    extra-substituters = [ "https://ghc-nix.cachix.org" ];
    extra-trusted-public-keys = [ "ghc-nix.cachix.org-1:wI8l3tirheIpjRnr2OZh6YXXNdK2fVQeOI4SVz/X8nA=" ];
  };
  inputs.ghc-nix.url = "github:alpmestan/ghc.nix";
  outputs = { ghc-nix, ... }:
    let
      userSettings = {
        # put your settings here
        withIde = true;
      };
    in
    {
      devShells = ghc-nix.lib.perSystem (system: { default = ghc-nix.legacy ({ inherit system; } // userSettings); });
    };
}
