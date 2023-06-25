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

  freebsdSysroot = stdenv.mkDerivation rec {
    pname = "freebsd-sysroot";
    version = "13.2-amd64";
    src = fetchurl {
      url = "https://download.freebsd.org/ftp/releases/amd64/13.2-RELEASE/base.txz";
      sha256 = "sha256-OpJQ96/XMLvidGkYWXVpSLPFepm82jDWXUauMAJZBvA=";
    };
    sourceRoot = ".";
    doBuild = false;
    dontFixup = true;
    installPhase = ''
      # adapted from https://github.com/cross-rs/cross/blob/main/docker/freebsd.sh#L184

      mkdir -p $out/lib/
      cp -r "usr/include" "$out"
      cp -r "lib/"* "$out/lib"
      cp "usr/lib/libc++.so.1" "$out/lib"
      cp "usr/lib/libc++.a" "$out/lib"
      cp "usr/lib/libcxxrt.a" "$out/lib"
      cp "usr/lib/libcompiler_rt.a" "$out/lib"
      cp "usr/lib"/lib{c,util,m,ssp_nonshared,memstat}.a "$out/lib"
      cp "usr/lib"/lib{rt,execinfo,procstat}.so.1 "$out/lib"
      cp "usr/lib"/libmemstat.so.3 "$out/lib"
      cp "usr/lib"/{crt1,Scrt1,crti,crtn}.o "$out/lib"
      cp "usr/lib"/libkvm.a "$out/lib"

      local lib=
      local base=
      local link=
      for lib in "''${out}/lib/"*.so.*; do
          base=$(basename "''${lib}")
          link="''${base}"
          # not strictly necessary since this will always work, but good fallback
          while [[ "''${link}" == *.so.* ]]; do
              link="''${link%.*}"
          done

          # just extra insurance that we won't try to overwrite an existing file
          local dstlink="''${out}/lib/''${link}"
          if [[ -n "''${link}" ]] && [[ "''${link}" != "''${base}" ]] && [[ ! -f "''${dstlink}" ]]; then
              ln -s "''${base}" "''${dstlink}"
          fi
      done

      ln -s libthr.so.3 "''${out}/lib/libpthread.so"
    '';
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
  in (recursiveMerge [{
      buildInputs = [cc];
      "CARGO_TARGET_${targetUpperCase}_RUSTFLAGS" = rustFlags;
      "CARGO_TARGET_${targetUpperCase}_LINKER" = "${cc.targetPrefix}cc";
      "AR_${targetUnderscore}" = "${cc.targetPrefix}ar";
      "CC_${targetUnderscore}" = "${cc.targetPrefix}cc";
      "CCX_${targetUnderscore}" = "${cc.targetPrefix}ccx";
    } rest]);

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
      rustFlags = "-C target-feature=+crt-static -Clink-arg=--sysroot=${freebsdSysroot} -Clink-arg=-L${freebsdSysroot}/lib";
      X86_64_UNKNOWN_FREEBSD_OPENSSL_DIR = freebsdSysroot;
      BINDGEN_EXTRA_CLANG_ARGS_x86_64_unknown_freebsd = "--sysroot=${freebsdSysroot}";
      LB = freebsdSysroot;
    };
    "x86_64-unknown-linux-musl" = (buildCrossArgs "x86_64-unknown-linux-musl" {
      cc = pkgsCross.musl64.stdenv.cc;
    });
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
