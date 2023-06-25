{
  rust-bin,
  lib,
  pkgsCross,
  callPackage,
  hostPlatform,
  naersk,
  stdenv,
  fetchurl,
  rustVersion ? "stable",
}: target: let
  inherit (lib.strings) replaceStrings toUpper;
  inherit (builtins) removeAttrs foldl';
  mingw_w64_cc = pkgsCross.mingwW64.stdenv.cc;
  windows = pkgsCross.mingwW64.windows;

  freebsdSysrootX86 = callPackage ./freebsd-sysroot.nix {
    arch = "amd64";
    sha256 = "sha256-OpJQ96/XMLvidGkYWXVpSLPFepm82jDWXUauMAJZBvA=";
    version = "13.2";
  };

  recursiveMerge = callPackage ./merge.nix {};

  buildCrossArgs = target: {
    rustFlags ? "-C target-feature=+crt-static",
    cc,
    ...
  } @ args: let
    targetUnderscore = replaceStrings ["-"] ["_"] target;
    targetUpperCase = toUpper targetUnderscore;
    rest = removeAttrs args ["rustFlags" "cc"];
  in (recursiveMerge [
    {
      buildInputs = [cc];
      "CARGO_TARGET_${targetUpperCase}_RUSTFLAGS" = rustFlags;
      "CARGO_TARGET_${targetUpperCase}_LINKER" = "${cc.targetPrefix}cc";
      "AR_${targetUnderscore}" = "${cc.targetPrefix}ar";
      "CC_${targetUnderscore}" = "${cc.targetPrefix}cc";
      "CCX_${targetUnderscore}" = "${cc.targetPrefix}ccx";
    }
    rest
  ]);

  defaultCrossArgs = {
    "armv7-unknown-linux-musleabihf" = buildCrossArgs "armv7-unknown-linux-musleabihf" {
      cc = pkgsCross.armv7l-hf-multiplatform.stdenv.cc;
    };
    "armv7-unknown-linux-gnueabihf" = buildCrossArgs "armv7-unknown-linux-gnueabihf" {
      cc = pkgsCross.armv7l-hf-multiplatform.stdenv.cc;
    };
    "aarch64-unknown-linux-musl" = buildCrossArgs "aarch64-unknown-linux-musl" {
      cc = pkgsCross.aarch64-multiplatform-musl.stdenv.cc;
    };
    "i686-unknown-linux-musl" = buildCrossArgs "i686-unknown-linux-musl" {
      cc = pkgsCross.musl32.stdenv.cc;
    };
    "x86_64-pc-windows-gnu" = buildCrossArgs "x86_64-pc-windows-gnu" {
      cc = pkgsCross.mingwW64.stdenv.cc;
      strictDeps = true;
      overrideMain = args: args // {buildInputs = [windows.pthreads];};
    };
    "x86_64-unknown-freebsd" = buildCrossArgs "x86_64-unknown-freebsd" {
      cc = pkgsCross.x86_64-freebsd.stdenv.cc;
      rustFlags = "-C target-feature=+crt-static -Clink-arg=--sysroot=${freebsdSysrootX86} -Clink-arg=-L${freebsdSysrootX86}/lib";
      X86_64_UNKNOWN_FREEBSD_OPENSSL_DIR = freebsdSysrootX86;
      BINDGEN_EXTRA_CLANG_ARGS_x86_64_unknown_freebsd = "--sysroot=${freebsdSysrootX86}";
    };
    "x86_64-unknown-linux-musl" = buildCrossArgs "x86_64-unknown-linux-musl" {
      cc = pkgsCross.musl64.stdenv.cc;
    };
  };

  crossArgs = options: recursiveMerge [defaultCrossArgs (options.crossArgs or {})];

  naersk' = callPackage naersk {};
  hostTarget = hostPlatform.config;
  naerskForTarget = let
    toolchain = rust-bin.${rustVersion}.latest.default.override {targets = [target];};
  in
    callPackage naersk {
      cargo = toolchain;
      rustc = toolchain;
    };
  crossArgsForTarget = options:
    if hostTarget != target
    then (crossArgs options).${target} or {}
    else {};
  args = options:
    {
      CARGO_BUILD_TARGET = target;
    }
    // (builtins.removeAttrs options ["crossArgs"])
    // (crossArgsForTarget options);
in rec {
  buildPackage = options: naerskForTarget.buildPackage (args options);
  defaultCrossArgsFor = target: defaultCrossArgs.${target} or {};
  defaultCrossArgsForTargets = targets: recursiveMerge (map defaultCrossArgsFor targets);
}
