# Usage examples:
#
#   nix-shell path/to/ghc.nix/ --pure --arg withDocs true --run \
#     './boot && ./configure $ALL_CONFIGURE_FLAGS && make -j4'
#
#   nix-shell path/to/ghc.nix/ --pure --run \
#     'env config_args=$ALL_CONFIGURE_FLAGS THREADS=2 ./validate --slow'
#
# You can also use this nix expression for building GHC with
# Hadrian, as follows:
#
#   nix-shell path/to/ghc.nix/ --run \
#     './boot && ./configure $ALL_CONFIGURE_FLAGS && hadrian/build.sh -j'
#
{ nixpkgs   ? import <nixpkgs> {}
, src       ? ./.
, bootghc   ? "ghc822"
, version   ? "8.5"
, withLlvm  ? false
, withDocs  ? false
, mkFile    ? null
}:

with nixpkgs;

let
    ourtexlive = texlive.combined.scheme-small;
    docsPackages = if withDocs then [ python3Packages.sphinx ourtexlive ] else [];
    noTest = pkg: haskell.lib.dontCheck pkg;

    deps =
      [ autoconf automake m4
        gmp.dev gmp.out
        ncurses.dev ncurses.out
        perl git file which python3
        (haskell.packages.${bootghc}.ghcWithPackages (ps:
	  [ (noTest ps.alex)
	    (noTest ps.happy)
	  ]
	))
      ]
      ++ docsPackages
      ++ stdenv.lib.optional withLlvm llvm_5 ;
    env = buildEnv {
      name = "ghc-build-environment";
      paths = deps;
    };

in

stdenv.mkDerivation rec {
  name = "ghc-${version}";
  buildInputs = [ env arcanist ];
  inherit src;
  postPatch = "patchShebangs .";
  preConfigure = ''
    echo Running preConfigure...
    echo ${version} > VERSION
    ((git log -1 --pretty=format:"%H") || echo dirty) > GIT_COMMIT_ID
    ./boot
  '' + stdenv.lib.optionalString (mkFile != null) ''
    cp ${mkFile} mk/build.mk
  '';
  configureFlags      = [ GMP_CONFIGURE_FLAGS ] ;
  CC                  = "${stdenv.cc}/bin/cc"   ;
  CC_STAGE0           = "${stdenv.cc}/bin/cc"   ;
  CFLAGS              = "-I${env}/include"      ;
  CPPFLAGS            = "-I${env}/include"      ;
  LDFLAGS             = "-L${env}/lib"          ;
  LD_LIBRARY_PATH     = "${env}/lib"            ;
  GMP_CONFIGURE_FLAGS = ''
    --with-gmp-includes=${env}/include
    --with-gmp-libraries=${env}/lib
    --with-curses-includes=${env}/include
    --with-curses-libraries=${env}/lib
  '';
  shellHook           = let llvmStr = if withLlvm then "YES" else "NO"; in ''
    # somehow, CC gets overriden so we set it again here.
    export CC=${stdenv.cc}/bin/cc

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
    echo "    LLVM            = ${llvmStr}"
    echo
    echo Please report bugs, problems or contributions to
    echo https://github.com/alpmestan/ghc.nix
  '';
  enableParallelBuilding = true;
  stripDebufFlags = [ "-S" ];
}
