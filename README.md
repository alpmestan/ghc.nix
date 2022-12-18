These Nix expressions provide an environment for GHC development.

This repository does not contain the GHC sources themselves, so make sure
you've cloned that repository first. The directions at https://ghc.dev are
an excellent place to start.

# Simple usage

## Quickstart

To enter an environment without cloning this repository you can run:

```
nix-shell https://github.com/alpmestan/ghc.nix/archive/master.tar.gz
```
or, with flakes enabled: 
```
nix develop github:alpmestan/ghc.nix
```

## Building GHC

These commands assume you have cloned this repository
to `~/ghc.nix`. `default.nix` has many parameters, all
of them optional. You should take a look at `ghc.nix`
for more details.


``` sh
$ echo "BuildFlavour = quick" > mk/build.mk
$ cat mk/build.mk.sample >> mk/build.mk
$ nix-shell ~/ghc.nix/shell.nix --run './boot && ./configure $CONFIGURE_ARGS && make -j4'
# works with --pure too
```

Note that we passed `$CONFIGURE_ARGS` to `./configure`. While this is
technically optional, this argument ensures that `configure` knows where the
compiler's dependencies (e.g. `gmp`, `libnuma`, `libdw`) are found, allowing
the compiler to be used even outsite of `nix-shell`. For convenience, the
`nix-shell` environment also exports a convenience command, `configure_ghc`,
which invokes `configure` as indicated.

If you are using zsh, you must pass `${=CONFIGURE_ARGS}` instead; otherwise
zsh will escape the spaces in `$CONFIGURE_ARGS` and interpret it as one single
argument. See also https://unix.stackexchange.com/a/19533/61132.

You can alternatively use Hadrian to build GHC:

``` sh
$ nix-shell ~/ghc.nix/shell.nix
# from the nix shell:
$ ./boot && ./configure $CONFIGURE_ARGS # In zsh, use ${=CONFIGURE_ARGS}
# example hadrian command: use 4 cores, build a 'quickest' flavoured GHC
# and place all the build artifacts under ./_mybuild/.
$ hadrian/build -j4 --flavour=quickest --build-root=_mybuild

# if you have never used cabal-install on your machine, you will likely
# need to run the following before the hadrian command:
$ cabal update
```

Or when you want to let nix fetch Hadrian dependencies enter the shell with

```sh
$ nix-shell ~/ghc.nix/shell.nix --arg withHadrianDeps true
```


## Using `ghcide`

You can also use `ghc.nix` to provide the right version of `ghcide` if you
want to use `ghcide` whilst developing on GHC. In order to do so, pass the `withIde`
argument to your `nix-shell` invocation.

```
nix-shell ~/.ghc.nix/shell.nix --arg withIde true
```

## Running `./validate`

``` sh
$ nix-shell ~/ghc.nix/shell.nix --pure --run 'THREADS=4 ./validate'
```

See other flags of `validate` by invoking `./validate --help` or just by reading its source code. Note that `./validate --slow` builds the compiler in debug mode which has the side-effect of disabling performance tests.

## Building and running for i686-linux from x86_64-linux

It's trivial!

``` sh
$ nix-shell ~/ghc.nix/shell.nix --arg nixpkgs '(import <nixpkgs> {}).pkgsi686Linux'
```

## Cachix

There is a Cachix cache ([ghc-nix](https://app.cachix.org/cache/ghc-nix)) which is filled by our CI. To use it, run the following command and follow the instructions:

```sh
cachix use ghc-nix
```

The cache contains Linux x64 binaries of all packages that are used during a default build (i.e. a build without any overridden arguments).

## Updating `ghc.nix`

- *to update everything*: `nix flake update`
- *to update other inputs*: run `nix flake lock --update-input other-input-name` 
- *available inputs*: 
  - `nixpkgs-unstable` (used to provide haskell-packages)
  - `nixpkgs` (used to provide some tooling, like texlive)
  - `flake-compat` (to ensure compatibility with pre-flake nix)
  - `all-cabal-hashes` (for the cabal-hashes of the haskell packages used) 
- *to use a certain commit for any of the inputs*: use flag `--override-input`, e.g. 
  ```sh
  nix develop --override-input all-cabal-hashes "github:commercialhaskell/all-cabal-hashes/f4b3c68d6b5b128503bc1139cfc66e0537bccedd"
  ```
- if you plan to upstream your modifications to `ghc.nix`, don't forget to run the formatter (`nix fmt`)

## Flake support

`ghc.nix` now also has basic flake support, `nixpkgs` and `nixpkgs-unstable` are pinned in the flake inputs
and the cabal hashes are pinned in the toplevel flake (not via the flake inputs because that is currently not 
possible in an idiomatic way) 

To format all nix code in this repo, run `nix fmt`, to enter a development shell, run `nix develop`.

## direnv

With nix-direnv support, it is possible to make [`direnv`](https://github.com/direnv/direnv/) load `ghc.nix`
upon entering your local `ghc` directory. Just put a `.envrc` containing `use flake /home/theUser/path/to/ghc.nix#` 
in the ghc directory. This works for all flake urls, so you can also put `use flake github:alpmestan/ghc.nix#` in 
there and it should work.

(*Note*: at the time of writing `.direnv` is not part of the `.gitignore` in ghc, so be careful to not accidentally 
commit it, it's the local cache of your development shell which makes loading it upon entering the directory instant)

## TODO

- We currently can't just invoke `nix-build` ([#1](https://github.com/alpmestan/ghc.nix/issues/1))
- We do not support all the cross compilation machinery that
  `head.nix` from nixpkgs supports.
