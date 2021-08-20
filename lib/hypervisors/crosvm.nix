{ self, nixpkgs }:

{ system
, vcpu
, mem
, nixos
, append
, interfaces ? []
, rootDisk
, volumes ? []
, shares ? []
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
      "--serial" "type=stdout,console=true,stdin=true"
      "-p" "console=ttyS0 quiet reboot=k panic=1 nomodules ro init=${nixos.config.system.build.toplevel}/init ${append}"
    ] ++
    builtins.concatMap ({ image, ... }:
      [ "--rwdisk" image ]
    ) volumes ++
    map (_:
      throw "virtiofs shares not implemented for CrosVM"
    ) shares ++
    map (_:
      throw "CrosVM networking is not configurable"
    ) interfaces ++
    [ "${nixos.config.system.build.kernel.dev}/vmlinux" ]
  );

  canShutdown = false;
  shutdownCommand =
    throw "'crosvm stop' is not graceful";
}
