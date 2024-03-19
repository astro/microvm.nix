{ self, nixpkgs, system, ... }:

let
  pkgs = nixpkgs.legacyPackages.${system};

in
{
  shellcheck = pkgs.runCommand "microvm-shellcheck"
    {
      src = self.packages.${system}.microvm;
      nativeBuildInputs = [ pkgs.shellcheck ];
    } ''
    shellcheck $src/bin/*
    touch $out
  '';
}

