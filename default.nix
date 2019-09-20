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
, bootghc   ? "ghc864"
, version   ? "8.9"
, hadrianCabal ? (builtins.getEnv "PWD") + "/hadrian/hadrian.cabal"
, useClang  ? false  # use Clang for C compilation
, withLlvm  ? false
, withDocs  ? true
, withIde   ? false
, withHadrianDeps ? false
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

    ghcide-src = fetchFromGitHub {
      owner = "hercules-ci";
      repo = "ghcide-nix";
      rev = "3156336ec3caf2f5f4bf1549a058800821f98c96";
      sha256 = "1x06fvb987i8y9g3x96p20knr69hivkk80fdbn1rrnc22jki8wh0";
    };

    ghcide = (import ghcide-src {})."ghcide-${bootghc}";

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
      ++ optional withIde ghcide
      ++ (if (! stdenv.isDarwin)
          then [ pxz ]
          else [
            libiconv
            darwin.libobjc
            darwin.apple_sdk.frameworks.Foundation
          ])
    );
    happy = noTest (hspkgs.callHackage "happy" "1.19.10" {});
    depsTools = with hspkgs; [ alex cabal-install happy ];

    hadrianCabalExists = builtins.pathExists hadrianCabal;
    hsdrv = if (withHadrianDeps &&
                builtins.trace "checking if ${toString hadrianCabal} is present:  ${if hadrianCabalExists then "yes" else "no"}"
                hadrianCabalExists)
            then hspkgs.callCabal2nix "hadrian" hadrianCabal {}
            else (hspkgs.mkDerivation rec {
              inherit version;
              pname   = "ghc-buildenv";
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
(hspkgs.shellFor rec {
  packages    = pkgset: [ hsdrv ];
  nativeBuildInputs = depsTools;
  buildInputs = depsSystem;

  hardeningDisable    = ["fortify"]                  ; ## Effectuated by cc-wrapper
  # Without this, we see a whole bunch of warnings about LANG, LC_ALL and locales in general.
  # In particular, this makes many tests fail because those warnings show up in test outputs too...
  # The solution is from: https://github.com/NixOS/nix/issues/318#issuecomment-52986702
  LOCALE_ARCHIVE      = if stdenv.isLinux then "${glibcLocales}/lib/locale/locale-archive" else "";

  shellHook           = let toYesNo = b: if b then "YES" else "NO"; in ''
    # somehow, CC gets overriden so we set it again here.
    export CC=${stdenv.cc}/bin/cc
    export PATH=${happy}/bin:$PATH

    # "nix-shell --pure" resets LANG to POSIX, this breaks "make TAGS".
    export LANG="en_US.UTF-8"
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${gmp.out}/lib:${ncurses.out}/lib"

    ${lib.optionalString withDocs "export FONTCONFIG_FILE=${fonts}"}
  '';
})
