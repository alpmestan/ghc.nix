{ config, lib, system, pkgs, ... }: with lib; let
  cfg = config.settings;
in
{
  options.settings = {
    nixpkgs = mkOption {
      type = types.attrs;
      description = "the nixpkgs set used";
      example = "inputs.nixpkgs";
    };
    all-cabal-hashes = mkOption {
      type = types.path;
      description = "path to the all-cabal-hashes derivation used";
      example = "inputs.all-cabal-hashes.outPath";
    };
    wasi-sdk.package = mkOption {
      type = types.nullOr types.package;
      description = "the wasi-sdk package used";
      example = "inputs.ghc-wasm-meta.packages.x86_64-linux.wasi-sdk";
    };
    wasmtime.package = mkOption {
      type = types.nullOr types.package;
      description = "the wasmtime package used";
      example = "inputs.ghc-wasm-meta.packages.x86_64-linux.wasmtime";
    };
    bootghc = mkOption {
      type = types.str;
      default = "ghc96";
      description = ''
        The bootstrap `ghc` version
      '';
    };
    version = mkOption {
      type = types.str;
      default = "9.9";
      description = ''
        the version of `ghc` to be bootstrapped
      '';
    };
    crossTarget = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "the crossTarget to use";
      example = "javascript-unknown-ghcjs";
    };
    hadrianCabal = mkOption {
      type = types.nullOr types.path;
      description = ''
        where `hadrian` is to be found
      '';
    };
    clang.enable = mkEnableOption "whether Clang is to be used for C compilation";
    llvm.enable = mkEnableOption "whether `llvm` should be included in the `librarySystemDepends`";
    docs.enable = mkEnableOption "whether to include dependencies to compile docs";
    ghcid.enable = mkEnableOption "whether to include `ghcid`";
    ide.enable = mkEnableOption "whether to include `hls`";
    hadrianDeps.enable = mkEnableOption "whether to include dependencies for `hadrian`";
    dwarf.enable = mkEnableOption "whether to enable `libdw` unwinding support";
    numa.enable = mkEnableOption "whether to enable `numa` support";
    dtrace.enable = mkEnableOption "whether to include `linuxPackages.systemtap`";
    grind.enable = mkEnableOption "whether to include `valgrind`";
    EMSDK.enable = mkEnableOption ''
      whether to include `emscripten` for the js-backend
      will create an .emscripten_cache folder in your working directory of the shell for writing.
      EM_CACHE is set to that path, prevents sub word sized atomic kinds of issues
    '';
    wasm.enable = mkEnableOption "whether to include `wasi-sdk` & `wasmtime` for the ghc wasm backend";
    findNoteDef.enable = mkEnableOption ''
      install a shell script find_note_def; find_note_def "Adding a language extension" will point to the definition of the Note "Adding a language extension"
    '';
    extra-deps = mkOption {
      type = types.listOf lib.types.package;
      default = [ ];
      example = "[pkgs.time-ghc-modules]";
      description = "additional tools to include in the devShell";
    };
    shell = mkOption {
      internal = true;
      type = types.package;
      description = ''
        the devShell created by ghc.nix
      '';
    };
  };
  config.settings = {
    docs.enable = mkDefault true;
    grind.enable = mkDefault true;
    findNoteDef.enable = mkDefault true;
    ide.enable = mkDefault true;
    dwarf.enable = mkDefault pkgs.stdenv.isLinux;
    numa.enable = mkDefault pkgs.stdenv.isLinux;
    dtrace.enable = mkDefault pkgs.stdenv.isLinux;
    shell = with cfg; import ../ghc.nix {
      inherit system;
      useClang = clang.enable;
      withLlvm = llvm.enable;
      withDocs = docs.enable;
      withGhcid = ghcid.enable;
      withIde = ide.enable;
      withHadrianDeps = hadrianDeps.enable;
      withDwarf = dwarf.enable;
      withNuma = numa.enable;
      withDtrace = dtrace.enable;
      withGrind = grind.enable;
      withEMSDK = EMSDK.enable;
      withWasm = wasm.enable;
      withFindNoteDef = findNoteDef.enable;
      wasmtime = wasmtime.package;
      wasi-sdk = wasi-sdk.package;
      inherit
        hadrianCabal
        version
        bootghc
        all-cabal-hashes
        nixpkgs
        ;
    };
  };
}
