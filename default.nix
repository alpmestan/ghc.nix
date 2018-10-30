# Usage examples:
#
#   nix-shell path/to/ghc.nix/ --pure --run './boot && ./configure && make -j4'
#   nix-shell path/to/ghc.nix/        --run 'hadrian/build.sh -c -j4 --flavour=quickest'
#   nix-shell path/to/ghc.nix/        --run 'THREADS=4 ./validate --slow'
#
{ nixpkgs   ? import <nixpkgs> {}
, bootghc   ? "ghc843"
, version   ? "8.7"
, useClang  ? false  # use Clang for C compilation
, withLlvm  ? false
, withDocs  ? true
, withDwarf ? nixpkgs.stdenv.isLinux  # enable libdw unwinding support
, withNuma  ? nixpkgs.stdenv.isLinux
, mkFile    ? null
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

    ourtexlive =
      nixpkgs.texlive.combine {
        inherit (nixpkgs.texlive) scheme-small collection-xetex fncychap titlesec tabulary varwidth framed capt-of wrapfig needspace dejavu-otf helvetic; };
    fonts = nixpkgs.makeFontsConf { fontDirectories = [ nixpkgs.dejavu_fonts ]; };
    docsPackages = if withDocs then [ python3Packages.sphinx ourtexlive ] else [];

    deps =
      [ autoconf automake m4
        gmp.dev gmp.out glibcLocales
        ncurses.dev ncurses.out
        perl git file which python3
        (hspkgs.ghcWithPackages (ps: [ ps.alex ps.happy ]))
        xlibs.lndir  # for source distribution generation
        cabal-install
        zlib.out
        zlib.dev
      ]
      ++ docsPackages
      ++ stdenv.lib.optional withLlvm llvm_6
      ++ stdenv.lib.optional withNuma numactl
      ++ stdenv.lib.optional withDwarf elfutils ;

    env = buildEnv {
      name = "ghc-build-environment";
      paths = deps;
    };

in

stdenv.mkDerivation rec {
  name = "ghc-${version}";
  buildInputs = [ env arcanist ];
  hardeningDisable = [ "fortify" ];
  phases = ["nobuild"];
  postPatch = "patchShebangs .";
  preConfigure = ''
    echo Running preConfigure...
    echo ${version} > VERSION
    ((git log -1 --pretty=format:"%H") || echo dirty) > GIT_COMMIT_ID
    ./boot
  '' + stdenv.lib.optionalString (mkFile != null) ''
    cp ${mkFile} mk/build.mk
  '';
  # N.B. CC gets overridden by stdenv
  CC                  = "${stdenv.cc}/bin/cc"        ;
  CC_STAGE0           = CC                           ;
  CFLAGS              = "-I${env}/include"           ;
  CPPFLAGS            = "-I${env}/include"           ;
  LDFLAGS             = "-L${env}/lib"               ;
  LD_LIBRARY_PATH     = "${env}/lib"                 ;
  GMP_LIB_DIRS        = "${env}/lib"                 ;
  GMP_INCLUDE_DIRS    = "${env}/include"             ;
  CURSES_LIB_DIRS     = "${env}/lib"                 ;
  CURSES_INCLUDE_DIRS = "${env}/include"             ;
  configureFlags      = lib.concatStringsSep " "
    ( lib.optional withDwarf "--enable-dwarf-unwind" ) ;

  shellHook           = let toYesNo = b: if b then "YES" else "NO"; in ''
    # somehow, CC gets overriden so we set it again here.
    export CC=${stdenv.cc}/bin/cc

    ${lib.optionalString withDocs "export FONTCONFIG_FILE=${fonts}"}

    # export NIX_LDFLAGS+= " -rpath ${src}/inplace/lib/ghc-${version}"

    echo Entering a GHC development shell with CFLAGS, CPPFLAGS, LDFLAGS and
    echo LD_LIBRARY_PATH correctly set, to be picked up by ./configure.
    echo
    echo "    CC              = $CC"
    echo "    CC_STAGE0       = $CC_STAGE0"
    echo "    CFLAGS          = $CFLAGS"
    echo "    CPPFLAGS        = $CPPFLAGS"
    echo "    LDFLAGS         = $LDFLAGS"
    echo "    LD_LIBRARY_PATH = ${env}/lib"
    echo "    LLVM            = ${toYesNo withLlvm}"
    echo "    libdw           = ${toYesNo withDwarf}"
    echo "    numa            = ${toYesNo withNuma}"
    echo "    configure flags = ${configureFlags}"
    echo
    echo Please report bugs, problems or contributions to
    echo https://github.com/alpmestan/ghc.nix
  '';
  enableParallelBuilding = true;
  NIX_BUILD_CORES = cores;
  stripDebugFlags = [ "-S" ];

  # Without this, we see a whole bunch of warnings about LANG, LC_ALL and locales in general.
  # In particular, this makes many tests fail because those warnings show up in test outputs too...
  # The solution is from: https://github.com/NixOS/nix/issues/318#issuecomment-52986702
  LOCALE_ARCHIVES = "${glibcLocales}/lib/locale/locale-archive";

  nobuild = ''
    echo Do not run this derivation with nix-build, it can only be used with nix-shell
  '';
}
