{
  rust-bin,
  lib,
  pkgsCross,
  callPackage,
  hostPlatform,
  naersk,
}: target: let
  mingw_w64_cc = pkgsCross.mingwW64.stdenv.cc;
  windows = pkgsCross.mingwW64.windows;

  crossArgs = options:
    {
      "armv7-unknown-linux-musleabihf" = {
        nativeBuildInputs = [pkgsCross.armv7l-hf-multiplatform.stdenv.cc];
        CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABIHF_RUSTFLAGS = "-C target-feature=+crt-static";
        CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABIHF_LINKER = "${pkgsCross.armv7l-hf-multiplatform.stdenv.cc.targetPrefix}cc";
      };
      "aarch64-unknown-linux-musl" = {
        nativeBuildInputs = [pkgsCross.aarch64-multiplatform-musl.stdenv.cc];
        CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_RUSTFLAGS = "-C target-feature=+crt-static";
        CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER = "${pkgsCross.aarch64-multiplatform-musl.stdenv.cc.targetPrefix}cc";
      };
      "i686-unknown-linux-musl" = {
        nativeBuildInputs = [pkgsCross.musl32.stdenv.cc];
        CARGO_TARGET_I686_UNKNOWN_LINUX_MUSL_RUSTFLAGS = "-C target-feature=+crt-static";
        CARGO_TARGET_I686_UNKNOWN_LINUX_MUSL_LINKER = "${pkgsCross.musl32.stdenv.cc.targetPrefix}cc";
      };
      "x86_64-pc-windows-gnu" = {
        strictDeps = true;
        nativeBuildInputs = [mingw_w64_cc];
        # only add pthreads when building the final package, not when building the dependencies
        # otherwise it interferes with building build scripts
        overrideMain = args: args // {buildInputs = [windows.pthreads];};

        CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = "${mingw_w64_cc.targetPrefix}cc";
      };
    }
    // (options.crossArgs or {});

  naersk' = callPackage naersk {};
  hostTarget = hostPlatform.config;
  naerskForTarget = let
    toolchain = rust-bin.stable.latest.default.override {targets = [target];};
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
in {
  buildPackage = options: naerskForTarget.buildPackage (args options);
}
