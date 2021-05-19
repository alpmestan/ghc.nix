Simple usage
============

## Quickstart

To enter an environment without cloning this repository you can run:

```
nix-shell https://github.com/alpmestan/ghc.nix/archive/master.tar.gz
```

## Building GHC

These commands assume you have cloned this repository
to `~/ghc.nix`. `default.nix` has many parameters, all
of them optional. You should take a look at `default.nix`
for more details.


``` sh
$ echo "BuildFlavour = quick" > mk/build.mk
$ cat mk/build.mk.sample >> mk/build.mk
$ nix-shell ~/ghc.nix/ --run './boot && ./configure $CONFIGURE_ARGS && make -j4'
# works with --pure too
```

Note that we passed `$CONFIGURE_ARGS` to `./configure`. While this is
technically optional, this argument ensures that `configure` knows where the
compiler's dependencies (e.g. `gmp`, `libnuma`, `libdw`) are found, allowing
the compiler to be used even outsite of `nix-shell`. For convenience, the
`nix-shell` environment also exports a convenience command, `configure_ghc`,
which invokes `configure` as indicated.

You can alternatively use Hadrian to build GHC:

``` sh
$ nix-shell ~/ghc.nix/
# from the nix shell:
$ ./boot && ./configure $CONFIGURE_ARGS
# example hadrian command: use 4 cores, build a 'quickest' flavoured GHC
# and place all the build artifacts under ./_mybuild/.
$ hadrian/build -j4 --flavour=quickest --build-root=_mybuild
# you could also ask hadrian to boot and configure for you, with -c

# if you have never used cabal-install on your machine, you will likely
# need to run the following before the hadrian command:
$ cabal update
```


## Using `ghcide`

You can also use `ghc.nix` to provide the right version of `ghcide` if you
want to use `ghcide` whilst developing on GHC. In order to do so, pass the `withIde`
argument to your `nix-shell` invocation.

```
nix-shell ~/.ghc.nix --arg withIde true
```

## Running `./validate`

``` sh
$ nix-shell ~/ghc.nix/ --pure --run 'THREADS=4 ./validate'
```

See other flags of `validate` by invoking `./validate --help` or just by reading its source code. Note that `./validate --slow` builds the compiler in debug mode which has the side-effect of disabling performance tests.

## Building and running for i686-linux from x86_64-linux

It's trivial!

``` sh
$ nix-shell ~/ghc.nix/ --arg nixpkgs '(import <nixpkgs> {}).pkgsi686Linux'
```

## Cross Compiling

This section describes how to build a cross-compiler, i.e. a compiler that runs
on one platform (like e.g. `amd64`) and produces code for another (e.g.
`aarch64`).

Currently this only works with a Makefile-based build. Hadrian uses the boot
GHC package manager to create the package database and old GHC package database
formats are incompatible to latest GHC versions.

### Create a cross-compiler Makefile

Put a file like this into `mk/build.mk`:

```Makefile
BuildFlavour = quick-cross
ifneq "$(BuildFlavour)" ""
include mk/flavours/$(BuildFlavour).mk
endif
Stage1Only = YES
HADDOCK_DOCS = NO
BUILD_SPHINX_HTML = NO
BUILD_SPHINX_PDF = NO
GhcLibHcOpts += -fPIC -keep-s-file
GhcRtsHcOpts += -fPIC
```

This will create a LLVM-based backend. It's crucial that the build is stopped
at `stage1` (`Stage1Only = YES`), because later stages are built with
previously compiled GHCs, that would create binaries for the target platform...

### Enter a cross-compiling nix enviroment

I prefer to use a `shell.nix` file to avoid long command lines. Put a
`shell.nix` into the GHC root directory:

```nix
import ghc.nix/default.nix {
    version = "9.1";
    withDocs = false;
    withHadrianDeps = true;
    crossTargetArch = "aarch64-unknown-linux-gnu";
    nixCrossTools = "aarch64-multiplatform";
    withLlvm = true;
    withDwarf = false;
}
```

`crossTargetArch` is the arch identifier; processor, operating system, ABI,
etc. It's the target of the GHC to built. `nixCrossTools` defines which tools
to use from `nixpkgs.pkgsCross`.

You can enter the enviroment by simply calling `nix-shell`.

### Boot, configure and make

```bash
./boot && configure_ghc
make -j
```

`configure_ghc` sets up the paths to all required libraries.

## Cachix

There is a Cachix cache ([ghc-nix](https://app.cachix.org/cache/ghc-nix)) which is filled by our CI. To use it, run the following command and follow the instructions:

```sh
cachix use ghc-nix
```

The cache contains Linux x64 binaries of all packages that are used during a default build (i.e. a build without any overridden arguments).

## Updating `ghc.nix`

We are using [niv](https://github.com/nmattia/niv) for dependency management of `ghc.nix`.
Our main external dependencies are `nixpkgs` and `ghcide-nix`.
To update the revisions of those dependencies, you need to run:
``` sh
$ niv update
```

If you want to only update a single dependency, e.g. ghcide, you may run
``` sh
$ niv update ghcide-nix
```

If you need to switch the branch of nixpkgs, you need to run `niv update nixpkgs -b <branch-name>`.
As an example, assume you want to use the nightly nixpkgs channel, you run:

``` sh
$ niv update nixpkgs -b nixos-unstable
```

After a brief wait time, the revision is updated.

## TODO

- We currently can't just invoke `nix-build` ([#1](https://github.com/alpmestan/ghc.nix/issues/1))
- We do not support all the cross compilation machinery that
  `head.nix` from nixpkgs supports.
