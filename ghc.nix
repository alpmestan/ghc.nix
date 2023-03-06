# Usage examples:
#
#   nix-shell path/to/ghc.nix/ --pure --run './boot && ./configure && make -j4'
#   nix-shell path/to/ghc.nix/        --run 'hadrian/build -c -j4 --flavour=quickest'
#   nix-shell path/to/ghc.nix/        --run 'THREADS=4 ./validate --slow'
#
let
  pkgsFor = nixpkgs: system:
    import nixpkgs { inherit system; overlays = [ ]; config = { }; };

in

{ system ? builtins.currentSystem
, nixpkgs
, nixpkgs-unstable
, all-cabal-hashes
, bootghc ? "ghc924"
, version ? "9.3"
, hadrianCabal ? (builtins.getEnv "PWD") + "/hadrian/hadrian.cabal"
, useClang ? false  # use Clang for C compilation
, withLlvm ? false
, withDocs ? true
, withGhcid ? false
, withIde ? false
, withHadrianDeps ? false
, withDwarf ? (pkgsFor nixpkgs system).stdenv.isLinux  # enable libdw unwinding support
, withNuma ? (pkgsFor nixpkgs system).stdenv.isLinux
, withDtrace ? (pkgsFor nixpkgs system).stdenv.isLinux
, withGrind ? !((pkgsFor nixpkgs system).valgrind.meta.broken or false)
, withEMSDK ? false                    # load emscripten for js-backend
}:

let
  overlay = self: super: {
    haskell = super.haskell // {
      packages = super.haskell.packages // {
        ${bootghc} = super.haskell.packages.${bootghc}.override (old: {
          inherit all-cabal-hashes;
          overrides =
            self.lib.composeExtensions
              (old.overrides or (_: _: { }))
              (_hself: hsuper: {
                ormolu =
                  if self.system == "aarch64-darwin"
                  then
                    self.haskell.lib.overrideCabal
                      hsuper.ormolu
                      (_: { enableSeparateBinOutput = false; })
                  else
                    hsuper.ormolu;
              });
        });
      };
    };
  };

  pkgs = import nixpkgs { inherit system; overlays = [ overlay ]; };

  pkgs-unstable =
    import nixpkgs-unstable { inherit system; overlays = [ overlay ]; };
in

with pkgs;

let
  llvmForGhc =
    if lib.versionAtLeast version "9.1"
    then llvm_10
    else llvm_9;

  stdenv =
    if useClang
    then pkgs.clangStdenv
    else pkgs.stdenv;
  noTest = haskell.lib.dontCheck;

  hspkgs = haskell.packages.${bootghc}.override {
    inherit all-cabal-hashes;
  };

  ghc = haskell.compiler.${bootghc};

  ourtexlive =
    pkgs.texlive.combine {
      inherit (pkgs.texlive)
        scheme-medium collection-xetex fncychap titlesec tabulary varwidth
        framed capt-of wrapfig needspace dejavu-otf helvetic upquote;
    };
  fonts = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };
  docsPackages = if withDocs then [ python3Packages.sphinx ourtexlive ] else [ ];

  depsSystem = with lib; (
    [
      autoconf
      automake
      m4
      less
      gmp.dev
      gmp.out
      glibcLocales
      ncurses.dev
      ncurses.out
      perl
      git
      file
      which
      python3
      xorg.lndir # for source distribution generation
      zlib.out
      zlib.dev
      hlint
    ]
    ++ docsPackages
    ++ optional withLlvm llvmForGhc
    ++ optional withGrind valgrind
    ++ optional withEMSDK emscripten
    ++ optional withNuma numactl
    ++ optional withDwarf elfutils
    ++ optional withGhcid ghcid
    ++ optional withIde (pkgs-unstable.haskell-language-server.override { supportedGhcVersions = [ (builtins.replaceStrings [ "." ] [ "" ] ghc.version) ]; })
    ++ optional withIde pkgs-unstable.clang-tools # N.B. clang-tools for clangd
    ++ optional withDtrace linuxPackages.systemtap
    ++ (if (! stdenv.isDarwin)
    then [ pxz ]
    else [
      libiconv
      darwin.libobjc
      darwin.apple_sdk.frameworks.Foundation
    ])
  );

  happy =
    if lib.versionAtLeast version "9.1"
    then noTest (hspkgs.callHackage "happy" "1.20.0" { })
    else noTest (haskell.packages.ghc865Binary.callHackage "happy" "1.19.12" { });

  alex =
    if lib.versionAtLeast version "9.1"
    then noTest (hspkgs.callHackage "alex" "3.2.6" { })
    else noTest (hspkgs.callHackage "alex" "3.2.5" { });

  # A convenient shortcut
  configureGhc = writeShellScriptBin "configure_ghc" "./configure $CONFIGURE_ARGS $@";
  validateGhc = writeShellScriptBin "validate_ghc" "config_args='$CONFIGURE_ARGS' ./validate $@";

  depsTools = [ happy alex hspkgs.cabal-install configureGhc validateGhc ];

  hadrianCabalExists = builtins.pathExists hadrianCabal;
  hsdrv =
    if (withHadrianDeps &&
      builtins.trace "checking if ${toString hadrianCabal} is present:  ${if hadrianCabalExists then "yes" else "no"}"
        hadrianCabalExists)
    then hspkgs.callCabal2nix "hadrian" hadrianCabal { }
    else
      (hspkgs.mkDerivation rec {
        inherit version;
        pname = "ghc-buildenv";
        license = "BSD";
        src = builtins.filterSource (_: _: false) ./.;

        libraryHaskellDepends = with hspkgs; lib.optionals withHadrianDeps [
          extra
          QuickCheck
          shake
          unordered-containers
        ];
        librarySystemDepends = depsSystem;
      });
in
hspkgs.shellFor rec {
  packages = _pkgset: [ hsdrv ];
  nativeBuildInputs = depsTools;
  buildInputs = depsSystem;
  passthru.pkgs = pkgs;

  hardeningDisable = [ "fortify" ]; ## Effectuated by cc-wrapper
  # Without this, we see a whole bunch of warnings about LANG, LC_ALL and locales in general.
  # In particular, this makes many tests fail because those warnings show up in test outputs too...
  # The solution is from: https://github.com/NixOS/nix/issues/318#issuecomment-52986702
  LOCALE_ARCHIVE = if stdenv.isLinux then "${glibcLocales}/lib/locale/locale-archive" else "";
  CONFIGURE_ARGS = [
    "--with-gmp-includes=${gmp.dev}/include"
    "--with-gmp-libraries=${gmp}/lib"
    "--with-curses-includes=${ncurses.dev}/include"
    "--with-curses-libraries=${ncurses.out}/lib"
  ] ++ lib.optionals withNuma [
    "--with-libnuma-includes=${numactl}/include"
    "--with-libnuma-libraries=${numactl}/lib"
  ] ++ lib.optionals withDwarf [
    "--with-libdw-includes=${elfutils.dev}/include"
    "--with-libdw-libraries=${elfutils.out}/lib"
    "--enable-dwarf-unwind"
  ];

  shellHook = ''
    # somehow, CC gets overridden so we set it again here.
    export CC=${stdenv.cc}/bin/cc
    export GHC=$NIX_GHC
    export GHCPKG=$NIX_GHCPKG
    export HAPPY=${happy}/bin/happy
    export ALEX=${alex}/bin/alex
    ${lib.optionalString withEMSDK "export EMSDK=${emscripten}"}
    ${lib.optionalString withEMSDK "export EMSDK_LLVM=${emscripten}/bin/emscripten-llvm"}
    ${lib.optionalString withLlvm "export LLC=${llvmForGhc}/bin/llc"}
    ${lib.optionalString withLlvm "export OPT=${llvmForGhc}/bin/opt"}

    # "nix-shell --pure" resets LANG to POSIX, this breaks "make TAGS".
    export LANG="en_US.UTF-8"
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${lib.makeLibraryPath depsSystem}"
    unset LD

    ${lib.optionalString withDocs "export FONTCONFIG_FILE=${fonts}"}

    >&2 echo "Recommended ./configure arguments (found in \$CONFIGURE_ARGS:"
    >&2 echo "or use the configure_ghc command):"
    >&2 echo ""
    >&2 echo "  ${lib.concatStringsSep "\n  " CONFIGURE_ARGS}"
  '';
}
