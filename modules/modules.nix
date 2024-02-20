{ pkgs, system, lib, ... }: [
  ./ghc-nix-module.nix
  {
    _module.args.system = lib.mkDefault system;
    _module.args.pkgs = lib.mkDefault pkgs;
  }
]
