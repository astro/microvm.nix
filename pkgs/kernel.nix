{ self, nixpkgs, system }:

let
  pkgs = nixpkgs.legacyPackages.${system};
in {
  virtioKernel = (pkgs.linuxPackages_custom {
    inherit (pkgs.linuxPackages.kernel) version src;
    configfile = builtins.fetchurl {
      url = "https://mergeboard.com/files/blog/qemu-microvm/defconfig";
      sha256 = "0ml8v19ir3vmhd948n7c0k9gw8br4d70fd02bfxv9yzwl6r1gvd9";
    };
  }).kernel;
}
