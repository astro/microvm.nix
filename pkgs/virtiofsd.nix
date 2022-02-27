{ rustPlatform
, fetchFromGitLab
, libseccomp
, libcap_ng
}:

rustPlatform.buildRustPackage rec {
  name = "virtiofsd";
  version = "1.1.0";
  src = fetchFromGitLab {
    owner = "virtio-fs";
    repo = "virtiofsd";
    rev = "v${version}";
    sha256 = "1fqc3ib17p5rl0nkik491yq1n29lwwjm35437b0ykr9zcfxk67aq";
  };
  cargoSha256 = "0m95xgq7j5d9gc5gmsqk36mnxxnlhbpjmdc7gfbvyc2iyl4jd9gk";

  buildInputs = [ libseccomp libcap_ng ];
}
