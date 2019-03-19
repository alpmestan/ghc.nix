let
    rev = "1222e289b5014d17884a8b1c99f220c5e3df0b14";
    src = builtins.fetchGit {
      url = "https://github.com/nixos/nixpkgs";
      inherit rev;
    };
in
import src
