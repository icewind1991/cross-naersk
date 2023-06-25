{
  rust-bin,
  lib,
  pkgsCross,
  callPackage,
  hostPlatform,
  naersk,
  stdenv,
  fetchurl,
}: target: let
  mingw_w64_cc = pkgsCross.mingwW64.stdenv.cc;
  windows = pkgsCross.mingwW64.windows;

  crossArgs = options:
    {
      "armv7-unknown-linux-musleabihf" = let
        cc = pkgsCross.armv7l-hf-multiplatform.stdenv.cc;
      in {
        CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABIHF_RUSTFLAGS = "-C target-feature=+crt-static";
        CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABIHF_LINKER = "${cc}/bin/${cc.targetPrefix}cc";
      };
      "aarch64-unknown-linux-musl" = let
        cc = pkgsCross.aarch64-multiplatform-musl.stdenv.cc;
      in {
        buildInputs = [cc];
        CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_RUSTFLAGS = "-C target-feature=+crt-static";
        CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER = "${cc.targetPrefix}cc";
        AR_aarch64_unknown_linux_musl = "${cc.targetPrefix}ar";
        CC_aarch64_unknown_linux_musl = "${cc.targetPrefix}cc";
        CCX_aarch64_unknown_linux_musl = "${cc.targetPrefix}ccx";
      };
      "i686-unknown-linux-musl" = let
        cc = pkgsCross.musl32.stdenv.cc;
      in {
        CARGO_TARGET_I686_UNKNOWN_LINUX_MUSL_RUSTFLAGS = "-C target-feature=+crt-static";
        CARGO_TARGET_I686_UNKNOWN_LINUX_MUSL_LINKER = "${cc}/bin/${cc.targetPrefix}cc";
      };
      "x86_64-pc-windows-gnu" = let
        cc = pkgsCross.mingwW64.stdenv.cc;
      in {
        strictDeps = true;
        # only add pthreads when building the final package, not when building the dependencies
        # otherwise it interferes with building build scripts
        overrideMain = args: args // {buildInputs = [windows.pthreads];};

        CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = "${cc}/bin/${cc.targetPrefix}cc";
      };
      "x86_64-unknown-freebsd" = let
        cc = pkgsCross.x86_64-freebsd.stdenv.cc;
        bsdLib = stdenv.mkDerivation rec {
          pname = "freebsd-base-libs";
          version = "13.2-amd64";
          src = fetchurl {
            url = "https://download.freebsd.org/ftp/releases/amd64/13.2-RELEASE/base.txz";
            sha256 = "sha256-OpJQ96/XMLvidGkYWXVpSLPFepm82jDWXUauMAJZBvA=";
          };
          sourceRoot = ".";
          doBuild = false;
          dontFixup = true;
          installPhase = ''
            mkdir -p $out/lib/
            cp lib/*.so usr/lib/*.so $out/lib/
          '';
        };
      in {
        nativeBuildInputs = [cc bsdLib];
        CARGO_TARGET_X86_64_UNKNOWN_FREEBSD_RUSTFLAGS = "-C target-feature=+crt-static";
        CARGO_TARGET_X86_64_UNKNOWN_FREEBSD_LINKER = "${cc.targetPrefix}cc";
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
