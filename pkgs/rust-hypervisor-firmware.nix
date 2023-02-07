{ lib
, fetchFromGitHub
, fetchurl
, rustPlatform
}:

rustPlatform.buildRustPackage rec {
  pname = "rust-hypervisor-firmware";
  version = "0.4.2";

  src = fetchFromGitHub {
    owner = "cloud-hypervisor";
    repo = pname;
    rev = "v${version}";
    sha256 = lib.fakeHash;
  };

  cargoSha256 = lib.fakeHash;
}
