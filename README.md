# cross-naersk

(mostly) zero configuration rust cross compiling for nix with naersk

## Usage

Add this repo, [`naersk`](https://github.com/nix-community/naersk) and [`rust-overlay`](oxalica/rust-overlay) as a flake input:

```nix
inputs = {
    cross-naersk.url = "github:icewind1991/cross-naersk";
    naersk.url = "github:nix-community/naersk";
    rust-overlay.url = "github:oxalica/rust-overlay";
}
```

Add `rust-overlay` as overlay to nixpkgs

```nix
overlays = [ (import rust-overlay) ];
pkgs = (import nixpkgs) {
  inherit system overlays;
};
```

Setup cross-naersk

```nix
cross-naersk' = pkgs.callPackage cross-naersk {inherit naersk;};
```

Define your targets

```nix
targets = [
    "x86_64-unknown-linux-musl"
    "i686-unknown-linux-musl"
    "armv7-unknown-linux-musleabihf"
    "aarch64-unknown-linux-musl"
    "x86_64-pc-windows-gnu"
    "x86_64-unknown-freebsd"
];
```

Cross compile your package

```nix
packages = pkgs.lib.attrsets.genAttrs targets (target: cross-naersk'.buildPackage target {
    pname = "mypkg";
    root = ./.;
});
```

## Targets

Cross-naersk comes with configuration for the following targets:

- armv7-unknown-linux-musleabihf
- armv7-unknown-linux-gnueabihf
- aarch64-unknown-linux-musl
- aarch64-unknown-linux-gnu
- i686-unknown-linux-musl
- i686-unknown-linux-gnu
- x86_64-unknown-linux-musl
- x86_64-unknown-linux-gnu
- x86_64-pc-windows-gnu
- x86_64-unknown-freebsd

## Configuration

cross-naersk sets a number of configuration options for naersk by default to make cross compiling work out of the box for most cases.

In the event that your projects requires additional naersk options set for some targets to compile, you can pass target specific options using `crossArgs`.

```nix
cross-naersk'.buildPackage target {
    pname = "mypkg";
    root = ./.;
    crossArgs = {
      "x86_64-pc-windows-gnu" = {
        buildInputs = [pkgsCross.pkgsCross.mingwW64.openssl.dev];
      };
    };
})
```

### Rust version

You can change the rust version by passing a toolchain (from rust-overlay):

```nix
cross-naersk' = pkgs.callPackage cross-naersk {
    inherit naersk;
    toolchain = pkgs.rust-bin.beta.latest.default;
};
```

## Shell

Cross-naersk also comes with a helper for building a devshell with all the parts required for the cross compilation

```nix
devShells.default = cross-naersk'.mkShell targets {
    # your normal shell configuration
};
```

Using this you can use normal cargo commands to build for any of the specified targets (`cargo build --target aarch64-unknown-linux-musl`).