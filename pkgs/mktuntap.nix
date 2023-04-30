{ stdenv, fetchgit }:

stdenv.mkDerivation {
  pname = "mktuntap";
  version = "1.0-1";

  src = fetchgit {
    url = "https://spectrum-os.org/git/mktuntap";
    sha256 = "sha256-kKn6p9uY5GHV/bLakuCC1WR2BO/M/4xrAdqoeT9EcfU=";
    rev = "f8c85dd180da9f2e81f4f821397996990fc731f4";
  };

  makeFlags = [ "prefix=${placeholder "out"}" ];
}
