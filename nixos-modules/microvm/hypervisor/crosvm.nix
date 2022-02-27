{ config, pkgs, lib, ... }:
let
  inherit (config.microvm) vcpu mem user interfaces volumes shares socket;
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
          "-p" "console=ttyS0 reboot=k panic=1 nomodules ${toString config.microvm.kernelParams}"
        ] ++
        lib.optionals (socket != null) [
          "-s" socket
        ] ++
        builtins.concatMap ({ image, ... }:
          [ "--rwdisk" image ]
        ) volumes ++
        builtins.concatMap ({ proto, tag, source, ... }:
          let
            type = {
              "9p" = "p9";
              "virtiofs" = "fs";
            }.${proto};
          in [
            "--shared-dir" "${source}:${tag}:type=${type}"
          ]
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
