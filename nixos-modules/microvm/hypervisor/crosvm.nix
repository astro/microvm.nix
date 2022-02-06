{ config, pkgs, lib, ... }:
let
  inherit (config.microvm) vcpu mem user interfaces volumes shares;
  rootDisk = config.system.build.squashfs;
in {
  microvm.runner.crosvm = import ../../../pkgs/runner.nix {
    hypervisor = "crosvm";

    inherit config pkgs;

    command =
      if user != null
      then throw "crosvm will not change user"
      else lib.escapeShellArgs (
        [
          "${pkgs.crosvm}/bin/crosvm" "run"
          "-m" (toString mem)
          "-c" (toString vcpu)
          "-r" rootDisk
          "--serial" "type=stdout,console=true,stdin=true"
          "-p" "console=ttyS0 quiet reboot=k panic=1 nomodules ro init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}"
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
        [ "${config.system.build.kernel.dev}/vmlinux" ]
      );

    canShutdown = false;
    shutdownCommand =
      throw "'crosvm stop' is not graceful";
  };
}
