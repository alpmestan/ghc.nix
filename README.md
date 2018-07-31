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
$ sed -e '/BuildFlavour = quickest/ s/^#//' mk/build.mk.sample > mk/build.mk
$ nix-shell ~/ghc.nix/ --run './boot && ./configure && make -j4'
# works with --pure too
```

You can alternatively use Hadrian to build GHC:

``` sh
$ nix-shell ~/ghc.nix/
# from the nix shell:
$ ./boot && ./configure
# example hadrian command: use 4 cores, build a 'quickest' flavoured GHC
# and place all the build artifacts under ./_mybuild/.
$ hadrian/build.sh -j4 --flavour=quickest --build-root=_mybuild
# you could also ask hadrian to boot and configure for you, with -c
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

## TODO

- We currently can't just invoke `nix-build` ([#1](https://github.com/alpmestan/ghc.nix/issues/1))
- We do not support all the cross compilation machinery that
  `head.nix` from nixpkgs supports.
- Some tests actually break with GHCs built with the first
  command above.
