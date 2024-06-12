**This repository has been moved to https://gitlab.haskell.org/ghc/ghc.nix**

---

These Nix expressions provide an environment for GHC development.

This repository does not contain the GHC sources themselves, so make sure
you've cloned that repository first. The directions at https://ghc.dev are
an excellent place to start.

[![CI](https://github.com/alpmestan/ghc.nix/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/alpmestan/ghc.nix/actions/workflows/ci.yml)

# Simple usage

## Quickstart

To enter an environment without cloning this repository you can run:

```sh
nix-shell https://github.com/alpmestan/ghc.nix/archive/master.tar.gz --attr devShells.<your-system>.default
```
where `<your-system>` would be the nix name of your system, in the typical case this is one of
- `x86_64-linux` (for `x86_64` Linux systems)
- `aarch64-linux` (for ARM Linux systems)
- `x86_64-darwin` (for old macs that do not have apple silicon)
- `aarch64-darwin` (for macs with apple silicon)

Hence, an invocation on an `x86_64` Linux system would look like this:
```sh
nix-shell https://github.com/alpmestan/ghc.nix/archive/master.tar.gz --attr devShells.x86_64-linux.default
```

### Using flakes

This repository is flakes enabled, which means, that you can more easily get a `devShell` using:

```sh
nix develop github:alpmestan/ghc.nix
```

## Building GHC

These commands assume you have cloned this repository
to `~/ghc.nix`. `shell.nix` has many parameters, all
of them optional. You should take a look at `ghc.nix`
for more details.

```sh
$ nix-shell ~/ghc.nix/shell.nix
# from the nix shell:
$ ./boot && configure_ghc
# example hadrian command: use 4 cores, build a 'quickest' flavoured GHC
# and place all the build artifacts under ./_mybuild/.
$ hadrian/build -j4 --flavour=quickest --build-root=_mybuild

# if you have never used cabal-install on your machine, you will likely
# need to run the following before the hadrian command:
$ cabal update
```

> **Note**
>
> `configure_ghc` runs `./configure $CONFIGURE_ARGS`. While this is technically
> optional, this argument ensures that `configure` knows where the compiler's
> dependencies (e.g. `gmp`, `libnuma`, `libdw`) are found, allowing the compiler
> to be used even outsite of `nix-shell`. Plus, for the JavaScript cross
> compiler, `configure_ghc` actually runs the wrapper `emconfigure`!
>
> If you are using zsh and you want to run `./configure` directly, you must pass
> `${=CONFIGURE_ARGS}` instead; otherwise zsh will escape the spaces in
> `$CONFIGURE_ARGS` and interpret it as one single argument. See also
> https://unix.stackexchange.com/a/19533/61132.

When you want to let Nix fetch Hadrian dependencies enter the shell with

```sh
$ nix-shell ~/ghc.nix/shell.nix --arg withHadrianDeps true
```

When using flakes, this argument is automatically applied.

## Using `haskell-language-server`

You can also use `ghc.nix` to provide the right version of
[`haskell-language-server` (`hls`)](https://github.com/haskell/haskell-language-server) if you
want to use `hls` whilst developing on GHC. In order to do so, pass the `withIde`
argument to your `nix-shell` invocation.

```sh
nix-shell ~/.ghc.nix/shell.nix --arg withIde true
```

When using flakes, this argument is also automatically applied.


```sh
$ nix develop github:alpmestan/ghc.nix
# HLS is already available
```

## Running `./validate`

```sh
$ nix-shell ~/ghc.nix/shell.nix --pure --run 'THREADS=4 ./validate'
```

See other flags of `validate` by invoking `./validate --help` or just by reading its source code.

> **Note**
> `./validate --slow` builds the compiler in debug mode which has the side-effect of disabling performance tests.

## Building and running for i686-linux from x86_64-linux

It's trivial!

```sh
$ nix-shell ~/ghc.nix/shell.nix --arg nixpkgs '(import <nixpkgs> {}).pkgsi686Linux'
```

## Building a WebAsm or JavaScript cross-compiler

Both cross-compilers are supported with `nix-shell` or the flake-based `nix develop`.

`CC`, `CONFIGURE_ARGS`, etc. environment variables will be overridden to configure the cross-compiler.

Once in the shell, use `./boot && configure_ghc`, then proceed with hadrian as usual.

HLS should also just work.

### For WebAsm:

```sh
nix-shell ~/ghc.nix --arg withWasm true
# or
nix develop github:alpmestan/ghc.nix#wasm-cross
```

### For JavaScript:

```sh
nix-shell ~/ghc.nix --arg withEMSDK true
# or
nix develop github:alpmestan/ghc.nix#js-cross
```

**Note** for the JavaScript backend, use `bignum=native` or the `native_bignum`
transformer.

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
  - `nixpkgs` (used to provide some tooling, like texlive)
  - `flake-compat` (to ensure compatibility with pre-flake nix)
  - `all-cabal-hashes` (for the cabal-hashes of the haskell packages used)
- *to use a certain commit for any of the inputs*: use flag `--override-input`, e.g.
  ```sh
  nix develop --override-input all-cabal-hashes "github:commercialhaskell/all-cabal-hashes/f4b3c68d6b5b128503bc1139cfc66e0537bccedd"
  ```
  this is not yet support in `flake-compat` mode, you will have to manually set the version in the `flake.nix` by appending
  `/your-commit-hash` to the input you want to change, then running `nix flake lock --update-input input-you-want-to-update`.
  Of course you can also just manually pass your own `nixpkgs` version to the `shell.nix`, this will override the one
  provided by the flake.
- if you plan to upstream your modifications to `ghc.nix`, don't forget to run the formatter using `nix fmt`

## Flake support

`ghc.nix` now also has basic flake support, `nixpkgs` and the `cabal-hashes` are pinned in the flake inputs.

To format all nix code in this repository, run `nix fmt`, to enter a development shell, run `nix develop`.
- To change the settings of the `devShell` to your liking, just adjust the `userSettings` attribute-set in the top-level flake.

> **Warning**
> Building a derivation from the local (ghc) hadrian requires `builtins.getEnv` which is only available if `--impure` is passed.


### Using the flake template

It is common that you want to change the settings that `ghc.nix` uses to set up a `devShell`. Currently there is
no good way in `nix` to pass `nix` expressions to flakes.

This is why we provide a flake template that you can add to your git worktree as follows:
```sh
$ nix flake init -t github:alpmestan/ghc.nix
```

This will add three files to your worktree:
- a `flake.nix` which you can edit your `userSettings` in as usual
- a `flake.lock` file which pins the `ghc.nix` version and transitively `nixpkgs` and `all-cabal-hashes`
- a `.envrc` file for convenient use with `direnv`

## Legacy nix-commands support

We use `flake-compat` to ensure compatibility of the old nix commands with the new flake commands and to use the flake inputs pinned by
`nix` itself. Unfortunately there is a shortcoming of the current implementation of the flake nix commands that makes it so that you
cannot pass arguments to the `devShell`s. To ensure backwards compatibility, we call a function that we keep as flake output from the
`./shell.nix` file. Most importantly, this means that **the `shell.nix` in this repo doesn't behave like a normal `flake-compat` shell
but rather like a legacy `shell.nix` that can indeed be passed arguments**.
The `default.nix` behaves just like you would expect it to behave with the use of `flake-compat`.

The following table shows what `./ghc.nix` can be configured with; the first column is the name of the attribute to be configured, the second
argument the description of that argument, the third the default value for that argument and the third one, whether or not the `flake.nix`
takes over orchestration of this attribute, this is the case if they're either pinned by the lock-file (e.g. `nixpkgs`) or can introduce impurity
(e.g. `system`)

If you do not want to pass your arguments with `--arg`, but rather capture your passed arguments in a `.nix` file, you can locally create a
file, say `shell.nix` with the following contents:

```nix
import ./path/to/ghc.nix/shell.nix {
  withHadrianDeps = true;
  withIde = true;
  # ... and so on
}
```
be careful to specify the path to the `shell.nix`, not to the `default.nix`.

| attribute-name | description | default | orchestrated by nix flake |
| -- | -- | -- | -- |
| `system` | the system this is run on | `builtins.currentSystem` or flake system | ✅ |
| `nixpkgs` | the stable `nixpkgs` set used | `nixpkgs` as pinned in the lock-file | ✅ |
| `all-cabal-hashes` | the `all-cabal-hashes` version used | `all-cabal-hashes` as pinned in the lock-file | ✅ |
| `bootghc` | the bootstrap `ghc` version | `"ghc924"` | ❌ |
| `version` | the version of `ghc` to be bootstrapped | `"9.3"` | ❌ |
| `hadrianCabal` | where `hadrian` is to be found |  `(builtins.getEnv "PWD") + "/hadrian/hadrian.cabal"` | ❌ |
| `useClang` | whether Clang is to be used for C compilation | `false` | ❌ |
| `withLlvm` | whether `llvm` should be included in the `librarySystemDepends` | `false` | ❌ |
| `withDocs` | whether to include dependencies to compile docs | `true` | ❌ |
| `withGhcid` | whether to include `ghci` | `false` | ❌ |
| `withIde` | whether to include `hls` | `false` | ❌ |
| `withHadrianDeps` | whether to include dependencies for `hadrian` | `false` | ❌ |
| `withDwarf` | whether to enable `libdw` unwinding support | `nixpkgs.stdenv.isLinux` | ❌ |
| `withGdb` | whether to include `gdb` | `true` | ❌ |
| `withNuma` | whether to enable `numa` support | `nixpkgs.stdenv.isLinux` | ❌ |
| `withDtrace` | whether to include `linuxPackage.systemtap` |  `nixpkgs.stdenv.isLinux` | ❌ |
| `withGrind` | whether to include `valgrind` | `true` | ❌ |
| `withPerf` | whether to include `perf` | `true` | ❌ |
| `withEMSDK` | whether to include `emscripten` for the js-backend, will create an `.emscripten_cache` folder in your working directory of the shell for writing. `EM_CACHE` is set to that path, prevents [sub word sized atomic](https://gitlab.haskell.org/ghc/ghc/-/wikis/javascript-backend/building#configure-fails-with-sub-word-sized-atomic-operations-not-available) kinds of issues | `false` | ❌ |
| `withWasm` | whether to include `wasi-sdk` & `wasmtime` for the ghc wasm backend | `false` | ❌ |
| `withFindNoteDef` | install a shell script `find_note_def`; `find_note_def "Adding a language extension"` will point to the definition of the Note "Adding a language extension" | `true` | ❌ |

## `direnv`

With `nix-direnv` support, it is possible to make [`direnv`](https://github.com/direnv/direnv/) load `ghc.nix`
upon entering your local `ghc` directory. Just put a `.envrc` containing `use flake /home/theUser/path/to/ghc.nix#`
in the `ghc` directory. This works for all flake URLs, so you can also put `use flake github:alpmestan/ghc.nix#` in
there and it should work.

> **Warning**
> If you're building an older GHC
> ([not including this commit](https://gitlab.haskell.org/MangoIV/ghc/-/commit/be95cc85e25e9f60434d6f0d97fc3a2deae0f909)),
> be careful about not checking out `.direnv`,  it's the local cache of your development shell which makes loading it
> upon entering the directory instant.

## contributing

- we check formatting and linting in our CI, so please be careful to run `nix flake check --allow-import-from-derivation --impure`
  before submitting changes as a PR
- the tooling to run the linting is provided by a nix `devShell` which you can easily obtain by running `nix develop .#formatting`.
  Now you only have to run `pre-commit run --all` to check for linting and to reformat; using this `devShell`, the formatting
  will also be checked before committing. You can skip the check by passing `--no-verify` to the `git commit` command
- `ghc.nix` also offers `direnv` integration, so if you have it installed, just run `direnv allow` to automatically load the
  formatting `devShell` and the accompanying pre-commit hook.
