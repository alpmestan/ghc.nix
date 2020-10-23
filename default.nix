# Usage examples:
#
#   nix-shell path/to/ghc.nix/ --pure --run './boot && ./configure && make -j4'
#   nix-shell path/to/ghc.nix/        --run 'hadrian/build -c -j4 --flavour=quickest'
#   nix-shell path/to/ghc.nix/        --run 'THREADS=4 ./validate --slow'
#
let
  sources = import ./nix/sources.nix {};
in
{ nixpkgs   ? import (sources.nixpkgs) {}
, bootghc   ? "ghc883"
, version   ? "9.1"
, hadrianCabal ? (builtins.getEnv "PWD") + "/hadrian/hadrian.cabal"
, useClang  ? false  # use Clang for C compilation
, withLlvm  ? false
, withDocs  ? true
, withGhcid ? false
, withIde   ? false
, withHadrianDeps ? false
, withDwarf  ? nixpkgs.stdenv.isLinux  # enable libdw unwinding support
, withNuma   ? nixpkgs.stdenv.isLinux
, withDtrace ? nixpkgs.stdenv.isLinux
, withGrind ? true
, crossTargetArch ? null # E.g. "aarch64-unknown-linux-gnu"
, nixCrossTools ? null # E.g. "aarch64-multiplatform"
}:

with nixpkgs;

let
    llvmForGhc = if lib.versionAtLeast version "9.1"
                 then llvm_10
                 else llvm_9;

    stdenv =
      if useClang
      then nixpkgs.clangStdenv
      else nixpkgs.stdenv;
    noTest = pkg: haskell.lib.dontCheck pkg;

    hspkgs = haskell.packages.${bootghc}.override {
      all-cabal-hashes = sources.all-cabal-hashes;
    };

    ghcide = (import sources.ghcide-nix {})."ghcide-${bootghc}";

    ghc    = haskell.compiler.${bootghc};

    ourtexlive =
      nixpkgs.texlive.combine {
        inherit (nixpkgs.texlive)
          scheme-medium collection-xetex fncychap titlesec tabulary varwidth
          framed capt-of wrapfig needspace dejavu-otf helvetic upquote;
      };
    fonts = nixpkgs.makeFontsConf { fontDirectories = [ nixpkgs.dejavu_fonts ]; };
    docsPackages = if withDocs then [ python3Packages.sphinx ourtexlive ] else [];

    isCross = assert (nixCrossTools == null) == (crossTargetArch == null); nixCrossTools != null;

    depsSystem = with stdenv.lib; (
      [ autoconf automake m4 less
        gmp.dev gmp.out glibcLocales
        ncurses.dev ncurses.out
        perl git file which python3
        xlibs.lndir  # for source distribution generation
        zlib.out
        zlib.dev
        hlint
      ]
      ++ docsPackages
      ++ optional withLlvm llvmForGhc
      ++ optional withGrind valgrind
      ++ optional withNuma numactl
      ++ optional withDwarf elfutils
      ++ optional withGhcid ghcid
      ++ optionals withIde [ghcide]
      ++ optional withDtrace linuxPackages.systemtap
      ++ optionals isCross [
        # cross toolchain
        pkgsCross.${nixCrossTools}.buildPackages.binutils
        pkgsCross.${nixCrossTools}.stdenv.cc

        # cross libs
        linuxHeaders
        elf-header
        pkgsCross.${nixCrossTools}.gmp.dev
        pkgsCross.${nixCrossTools}.gmp.out
        pkgsCross.${nixCrossTools}.ncurses.dev
        pkgsCross.${nixCrossTools}.ncurses.out
        (optionalString withNuma pkgsCross.${nixCrossTools}.numactl)

        # TODO: Add withDwarf dependencies here.
        # The elfutils package currently doesn't cross-compile.

        # to execute cross-compiled programms.
        qemu
      ]
      ++ (if (! stdenv.isDarwin)
          then [ pxz ]
          else [
            libiconv
            darwin.libobjc
            darwin.apple_sdk.frameworks.Foundation
          ])
    );
    happy =
      if lib.versionAtLeast version "8.8"
      then noTest (hspkgs.callHackage "happy" "1.20.0" {})
      else hspkgs.happy_1_19_5;
    depsTools = [ happy hspkgs.alex hspkgs.cabal-install ];

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
    pkgsSource = if !isCross then
                    nixpkgs
                 else
                    pkgsCross.${nixCrossTools};
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
  CONFIGURE_ARGS      = [ "--with-gmp-includes=${pkgsSource.gmp.dev}/include"
                          "--with-gmp-libraries=${pkgsSource.gmp}/lib"
                          "--with-curses-libraries=${pkgsSource.ncurses.out}/lib"
                        ] ++ lib.optionals withNuma [
                          "--with-libnuma-includes=${pkgsSource.numactl}/include"
                          "--with-libnuma-libraries=${pkgsSource.numactl}/lib"
                        ] ++ lib.optionals withDwarf [
                          "--with-libdw-includes=${pkgsSource.elfutils}/include"
                          "--with-libdw-libraries=${pkgsSource.elfutils}/lib"
                          "--enable-dwarf-unwind"
                        ] ++ lib.optionals isCross [
                          "--target=${crossTargetArch}"
                          "--enable-bootstrap-with-devel-snapshot"
                        ];

  TARGET_DEPS_EXPORTS  = if !isCross then
      "export CC=${stdenv.cc}/bin/cc"
    else
      ''
        export NM=${crossTargetArch}-nm
        export LD=${crossTargetArch}-ld.gold
        export AR=${crossTargetArch}-ar
        export AS=${crossTargetArch}-as
        export CC=${crossTargetArch}-cc
        export CXX=${crossTargetArch}-cxx
      '';

  shellHook           = let toYesNo = b: if b then "YES" else "NO"; in ''
    # somehow, CC gets overriden so we set it again here.
    ${TARGET_DEPS_EXPORTS}
    export HAPPY=${happy}/bin/happy
    export ALEX=${hspkgs.alex}/bin/alex
    ${lib.optionalString withLlvm "export LLC=${llvmForGhc}/bin/llc"}
    ${lib.optionalString withLlvm "export OPT=${llvmForGhc}/bin/opt"}

    # "nix-shell --pure" resets LANG to POSIX, this breaks "make TAGS".
    export LANG="en_US.UTF-8"
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${lib.makeLibraryPath depsSystem}"
    unset LD

    ${lib.optionalString withDocs "export FONTCONFIG_FILE=${fonts}"}

    # A convenient shortcut
    configure_ghc() { ./configure $CONFIGURE_ARGS $@; }

    validate_ghc() { config_args="$CONFIGURE_ARGS" ./validate $@; }

    ${lib.optionalString isCross "echo 'Please make sure you only build up to Stage1 (see UserSettings.hs in hadrian).'"}
    >&2 echo "Recommended ./configure arguments (found in \$CONFIGURE_ARGS:"
    >&2 echo "or use the configure_ghc command):"
    >&2 echo ""
    >&2 echo "  ${lib.concatStringsSep "\n  " CONFIGURE_ARGS}"
  '';
})
