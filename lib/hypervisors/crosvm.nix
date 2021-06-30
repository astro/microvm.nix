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
in config // {
  command = nixpkgs.lib.escapeShellArgs (
    [
      "${pkgs.crosvm}/bin/crosvm" "run"
      "-m" (toString mem)
      "-c" (toString vcpu)
      "-r" rootDisk
      "--shared-dir" "/nix/store/:store"
      "--serial" "type=stdout,console=true,stdin=true"
      "-p" "console=ttyS0 verbose reboot=k panic=1 nomodules ro init=${nixos.config.system.build.toplevel}/init ${append}"
    ] ++
    builtins.concatMap ({ image, ... }:
      [ "--rwdisk" image ]
    ) volumes ++
    map (_:
      throw "CrosVM networking is not configurable"
    ) interfaces ++
    [ "${self.packages.${system}.cloudHypervisorKernel}/bzImage" ]
  );
}
