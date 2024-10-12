{ nixpkgs, ... }:

let
  nixosModulesPath = nixpkgs + "/nixos/modules";

in
{
  imports = [
    # system.build
    (nixosModulesPath + "/system/build.nix")
  ];

  nixpkgs = nixpkgs;
}
