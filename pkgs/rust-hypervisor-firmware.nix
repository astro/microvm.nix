{ lib
, rustPlatform
, targetPlatform
, lld
}:

let
  targetFile = "${{
    "x64" = "x86_64";
    "aa64" = "aarch64";
  }.${targetPlatform.efiArch}}-unknown-none.json";

  pname = "rust-hypervisor-firmware";
  version = "0.4.2";
  src = callPackage ./rust-hypervisor-firmware-src.nix {};

in

rustPlatform.buildRustPackage {
  inherit pname version src;

  cargoSha256 = "sha256-edi6/Md6KebKM3wHArZe1htUCg0/BqMVZKA4xEH25GI=";

  CARGO_BUILD_TARGET = targetFile;
  RUSTC_BOOTSTRAP = 1;

  nativeBuildInputs = [
    lld
  ];

  RUSTFLAGS = "-C linker=lld -C linker-flavor=ld.lld";

  doCheck = false;

  meta = {
    platforms = [ "x86_64-none" ];
  };
}
