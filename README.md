Simple usage
============

## Building GHC

These commands assume you have cloned this repository
to `~/ghc.nix`. `default.nix` has many parameters, all
of them optional. You should take a look at `default.nix`
for more details.


``` sh
$ echo 'BuildFlavour=quickest' > mk/build.mk
$ nix-shell ghc.nix/ [--pure] --arg withDocs true --run \
    './boot && ./configure $GMP_CONFIGURE_FLAGS && make -j4'
```

## Running `./validate`

``` sh
$ nix-shell ~/ghc.nix/ --pure --run \
    'env config_args=$GMP_CONFIGURE_ARGS THREADS=2 ./validate --slow'
```

## TODO

- We currently can't just invoke `nix-build` ([#1](https://github.com/alpmestan/ghc.nix/issues/1))
- We do not support all the cross compilation machinery that
  `head.nix` from nixpkgs supports.
- Some tests actually break with GHCs built with the first
  command above.
