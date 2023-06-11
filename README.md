# cross-naersk

(mostly) zero configuration rust cross compiling for nix with naersk

## Usage

Add this repo, [`naersk`](https://github.com/nix-community/naersk) and [`rust-overlay`](oxalica/rust-overlay) as a flake input:

```nix
inputs = {
    ...
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
];
```

Cross compile your package

```
packages = pkgs.lib.attrsets.genAttrs targets (target: (cross-naersk' target).buildPackage {
    pname = "mypkg";
    root = ./.;
});
```