{ self, nixpkgs }:

{ system
, vcpu
, mem
, nixos
, append
, interfaces ? []
, rootDisk
, volumes
, hostName
, ...
}@args:
let
  config = args // {
    inherit interfaces;
  };
  pkgs = nixpkgs.legacyPackages.${system};
  firectl = pkgs.firectl.overrideAttrs (oa: {
    # allow read-only root-drive
    postPatch = ''
      substituteInPlace options.go \
          --replace "IsReadOnly:   firecracker.Bool(false)," \
          "IsReadOnly:   firecracker.Bool(true),"
      '';
    });
in config // {
  command = nixpkgs.lib.escapeShellArgs (
    [
      "${firectl}/bin/firectl"
      "--firecracker-binary=${pkgs.firecracker}/bin/firecracker"
      "-m" (toString mem)
      "-c" (toString vcpu)
      "--kernel=${self.packages.${system}.virtioKernel.dev}/vmlinux"
      "--root-drive=${rootDisk}"
      "--kernel-opts=console=ttyS0 noapic reboot=k panic=1 pci=off nomodules ro quiet init=${nixos.config.system.build.toplevel}/init ${append}"
    ] ++
    map ({ image, ... }:
      "--add-drive=${image}:rw"
    ) volumes ++
    map ({ type ? "tap", id, mac }:
      if type == "tap"
      then "--tap-device=${id}/${mac}"
      else throw "Unsupported interface type ${type} for Firecracker"
    ) interfaces
  );
}
