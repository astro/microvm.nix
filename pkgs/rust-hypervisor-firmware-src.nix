{ fetchFromGitHub }:
let
  pname = "rust-hypervisor-firmware";
  version = "0.4.2";
in
fetchFromGitHub {
  owner = "cloud-hypervisor";
  repo = pname;
  rev = version;
  sha256 = "sha256-hKk5pcop8rb5Q+IVchcl+XhMc3DCBBPn5P+AkAb9XxI=";
}
