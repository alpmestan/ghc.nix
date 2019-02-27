# Usage examples:
#
#   nix-shell path/to/ghc.nix/ --pure --run './boot && ./configure && make -j4'
#   nix-shell path/to/ghc.nix/        --run 'hadrian/build.sh -c -j4 --flavour=quickest'
#   nix-shell path/to/ghc.nix/        --run 'THREADS=4 ./validate --slow'
#
let
  fetchNixpkgs = import ./nix/fetch-tarball-with-override.nix "custom_nixpkgs";
in
{ nixpkgsPin ? ./nix/pins/nixpkgs.src-json
, nixpkgs   ? import (fetchNixpkgs nixpkgsPin) {}
, bootghc   ? "ghc844"
, version   ? "8.7"
, useClang  ? false  # use Clang for C compilation
, withLlvm  ? false
, withDocs  ? true
, withDwarf ? nixpkgs.stdenv.isLinux  # enable libdw unwinding support
, withNuma  ? nixpkgs.stdenv.isLinux
, cores     ? 4
}:

with nixpkgs;

let
    stdenv =
      if useClang
      then nixpkgs.clangStdenv
      else nixpkgs.stdenv;
    noTest = pkg: haskell.lib.dontCheck pkg;

    hspkgs = haskell.packages.${bootghc};
    ghc    = haskell.compiler.${bootghc};

    ourtexlive =
      nixpkgs.texlive.combine {
        inherit (nixpkgs.texlive) scheme-small collection-xetex fncychap titlesec tabulary varwidth framed capt-of wrapfig needspace dejavu-otf helvetic; };
    fonts = nixpkgs.makeFontsConf { fontDirectories = [ nixpkgs.dejavu_fonts ]; };
    docsPackages = if withDocs then [ python3Packages.sphinx ourtexlive ] else [];

    depsSystem = with stdenv.lib; (
      [ autoconf automake m4
        gmp.dev gmp.out glibcLocales
        ncurses.dev ncurses.out
        perl git file which python3
        xlibs.lndir  # for source distribution generation
        zlib.out
        zlib.dev
      ]
      ++ docsPackages
      ++ optional withLlvm llvm_7
      ++ optional withNuma numactl
      ++ optional withDwarf elfutils
      ++ (if (! stdenv.isDarwin)
          then [ pxz ]
          else [
            libiconv
            darwin.libobjc
            darwin.apple_sdk.frameworks.Foundation
          ])
    );

    depsHaskell = with hspkgs; [
      alex
      cabal-install
      happy
      unordered-containers
    ];

    env = ghc;

    hsdrv = (hspkgs.mkDerivation rec {
      inherit version;
      pname   = "ghc-buildenv";
      license = "BSD";

      libraryHaskellDepends = depsHaskell;
    });
in
(hspkgs.shellFor rec {
  packages    = pkgset: [ hsdrv ];
  buildInputs = depsSystem;

  # N.B. CC gets overridden by stdenv
  CC                  = "${stdenv.cc}/bin/cc"        ;
  CC_STAGE0           = CC                           ;
  CFLAGS              = "-I${env}/include"           ;
  CPPFLAGS            = "-I${env}/include"           ;
  CURSES_INCLUDE_DIRS = "${env}/include"             ;
  CURSES_LIB_DIRS     = "${env}/lib"                 ;
  GMP_INCLUDE_DIRS    = "${env}/include"             ;
  GMP_LIB_DIRS        = "${env}/lib"                 ;
  hardeningDisable    = ["fortify"]                  ; ## Effectuated by cc-wrapper
  LDFLAGS             = "-L${env}/lib"               ;
  LD_LIBRARY_PATH     = "${env}/lib"                 ;
  # Without this, we see a whole bunch of warnings about LANG, LC_ALL and locales in general.
  # In particular, this makes many tests fail because those warnings show up in test outputs too...
  # The solution is from: https://github.com/NixOS/nix/issues/318#issuecomment-52986702
  LOCALE_ARCHIVE      = if stdenv.isLinux then "${glibcLocales}/lib/locale/locale-archive" else "";

  shellHook           = let toYesNo = b: if b then "YES" else "NO"; in ''
    # somehow, CC gets overriden so we set it again here.
    export CC=${stdenv.cc}/bin/cc

    # "nix-shell --pure" resets LANG to POSIX, this breaks "make TAGS".
    export LANG="en_US.UTF-8"

    ${lib.optionalString withDocs "export FONTCONFIG_FILE=${fonts}"}

    echo Entering a GHC development shell with CFLAGS, CPPFLAGS, LDFLAGS and
    echo LD_LIBRARY_PATH correctly set, to be picked up by ./configure.
    echo
    echo "    CC              = $CC"
    echo "    CC_STAGE0       = $CC_STAGE0"
    echo "    CFLAGS          = $CFLAGS"
    echo "    CPPFLAGS        = $CPPFLAGS"
    echo "    LDFLAGS         = $LDFLAGS"
    echo "    LD_LIBRARY_PATH = $LD_LIBRARY_PATH"
    echo "    LLVM            = ${toYesNo withLlvm}"
    echo "    libdw           = ${toYesNo withDwarf}"
    echo "    numa            = ${toYesNo withNuma}"
    echo
    echo Please report bugs, problems or contributions to
    echo https://github.com/alpmestan/ghc.nix
  '';
})
