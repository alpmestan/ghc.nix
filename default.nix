# Usage examples:
#
#   nix-shell path/to/ghc.nix/ --pure --run './boot && ./configure && make -j4'
#   nix-shell path/to/ghc.nix/        --run 'hadrian/build -c -j4 --flavour=quickest'
#   nix-shell path/to/ghc.nix/        --run 'THREADS=4 ./validate --slow'
#
{ bootghc   ? "ghc922"
, version   ? "9.3"
, hadrianCabal ? (builtins.getEnv "PWD") + "/hadrian/hadrian.cabal"
, nixpkgs
, nixpkgs-unstable
, cabal-hashes
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
, withEMSDK ? false                    # load emscripten for js-backend
}:

with nixpkgs;

let
    llvmForGhc = if lib.versionAtLeast version "9.1"
                 then if withEMSDK
                      then nixpkgs-unstable.llvmPackages_git.llvm # use the git version for js backend
                      else llvm_10
                 else llvm_9;

    stdenv =
      if useClang
      then nixpkgs.clangStdenv
      else if withEMSDK
        then nixpkgs-unstable.emscriptenStdenv
        else nixpkgs.stdenv;

    noTest = pkg: haskell.lib.dontCheck pkg;

    hspkgs = haskell.packages.${bootghc}.override {
      # all-cabal-hashes = cabal-hashes;
    };

    ghc    = haskell.compiler.${bootghc};

    ourtexlive =
      nixpkgs.texlive.combine {
        inherit (nixpkgs.texlive)
          scheme-medium collection-xetex fncychap titlesec tabulary varwidth
          framed capt-of wrapfig needspace dejavu-otf helvetic upquote;
      };
    fonts = nixpkgs.makeFontsConf { fontDirectories = [ nixpkgs.dejavu_fonts ]; };
    docsPackages = if withDocs then [ python3Packages.sphinx ourtexlive ] else [];

    # This provides the stuff we need from the emsdk
    emscripten = nixpkgs-unstable.emscripten.override { llvmPackages = nixpkgs-unstable.llvmPackages_git; };
    emsdk = linkFarm "emsdk" [
      { name = "upstream/bin"; path = llvmForGhc + "/bin"; }
      { name = "upstream/emscripten"; path = emscripten + "/bin"; }
      # { name = "emscripten_cache"; path = nixpkgs-unstable.emscripten + "/share/emscripten/cache"; }
    ];

    depsSystem = with lib; (
      [ autoconf automake m4 less
        gmp.dev gmp.out glibcLocales
        ncurses.dev ncurses.out
        perl git file which python3
        xorg.lndir  # for source distribution generation
        zlib.out
        zlib.dev
        hlint
      ]
      ++ docsPackages
      ++ optional withLlvm llvmForGhc
      ++ optional withGrind valgrind
      ++ optionals withEMSDK [ nixpkgs-unstable.llvm_14 nixpkgs-unstable.lld emsdk ]
      ++ optional withNuma  numactl
      ++ optional withDwarf elfutils
      ++ optional withGhcid ghcid
      ++ optional withIde (nixpkgs-unstable.haskell-language-server.override { supportedGhcVersions = [ (builtins.replaceStrings ["."] [""] ghc.version) ]; })
      ++ optional withIde nixpkgs-unstable.clang-tools # N.B. clang-tools for clangd
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
      then noTest (hspkgs.callHackage "happy" "1.20.0" {})
      else noTest (haskell.packages.ghc865Binary.callHackage "happy" "1.19.12" {});

    alex =
      if lib.versionAtLeast version "9.1"
      then noTest (hspkgs.callHackage "alex" "3.2.6" {})
      else noTest (hspkgs.callHackage "alex" "3.2.5" {});

    depsTools = [ happy alex hspkgs.cabal-install ];

    ghcjsBin = (builtins.getEnv "PWD") + "/inplace/ghcjs_toolchain";

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
  passthru.pkgs = pkgs;

  hardeningDisable    = ["fortify"]                  ; ## Effectuated by cc-wrapper
  # Without this, we see a whole bunch of warnings about LANG, LC_ALL and locales in general.
  # In particular, this makes many tests fail because those warnings show up in test outputs too...
  # The solution is from: https://github.com/NixOS/nix/issues/318#issuecomment-52986702
  LOCALE_ARCHIVE      = if stdenv.isLinux then "${glibcLocales}/lib/locale/locale-archive" else "";

  # We require some special handling for the JS-backend. Specifically emscripten
  # requires LLVM in the path but the JS-backend looks in a particular directory
  # for its tooling. Thus we set those paths up here, conditionally on the EMSDK
  # flag. Note that withEMSDK thus implies withLlvm.
  GHCJS_HOOK         = if withEMSDK
                       then ''export EMSDK=${emsdk}/upstream/emscripten
                              export EMSDK_LLVM=${emsdk}/upstream
                              export EMSDK_BIN=${emsdk}/upstream/bin
                              export EMCONFIGURE_JS=2
                              export PATH=${lib.makeBinPath [ ghcjsBin ]}:$PATH
                              export PATH=${emsdk}/upstream/emscripten:$PATH
                              export CC=${emsdk}/upstream/emscripten/emcc

                              # we have to copy from the nixpkgs because we cannot unlink the symlink and copy
                              # similarly exporting the cache to the nix store fails during configuration
                              # for some reason
                              cp -Lr ${emscripten}/share/emscripten/cache .emscripten_cache
                              chmod u+rwX -R .emscripten_cache
                              export EM_CACHE=.emscripten_cache
                            ''
                       else ''# somehow, CC gets overriden so we set it again here.
                              export CC=${stdenv.cc}/bin/cc
                            '';

  CONFIGURE_ARGS      = [ "--with-gmp-includes=${gmp.dev}/include"
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

  shellHook           = ''
    export GHC=$NIX_GHC
    export GHCPKG=$NIX_GHCPKG
    export HAPPY=${happy}/bin/happy
    export ALEX=${alex}/bin/alex
    ${GHCJS_HOOK}
    ${lib.optionalString (withLlvm) "export LLC=${llvmForGhc}/bin/llc"}
    ${lib.optionalString (withLlvm) "export OPT=${llvmForGhc}/bin/opt"}

    # "nix-shell --pure" resets LANG to POSIX, this breaks "make TAGS".
    export LANG="en_US.UTF-8"
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${lib.makeLibraryPath depsSystem}"
    unset LD

    ${lib.optionalString withDocs "export FONTCONFIG_FILE=${fonts}"}

    # A convenient shortcut
    configure_ghc() { ./configure $CONFIGURE_ARGS $@; }

    validate_ghc() { config_args="$CONFIGURE_ARGS" ./validate $@; }

    >&2 echo "Recommended ./configure arguments (found in \$CONFIGURE_ARGS:"
    >&2 echo "or use the configure_ghc command):"
    >&2 echo ""
    >&2 echo "  ${lib.concatStringsSep "\n  " CONFIGURE_ARGS}"
  '';
})
