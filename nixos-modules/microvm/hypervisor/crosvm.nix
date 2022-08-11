{ config, pkgs, lib, ... }:
let
  inherit (config.microvm) vcpu mem user interfaces volumes shares socket;
  rootDisk = config.system.build.squashfs;
  mktuntap = pkgs.callPackage ../../../pkgs/mktuntap.nix {};
  interfaceFdOffset = 3;
in {
  microvm.runner.crosvm = import ../../../pkgs/runner.nix {
    hypervisor = "crosvm";

    inherit config pkgs;

    command =
      if user != null
      then throw "crosvm will not change user"
      else lib.escapeShellArgs (
        lib.concatLists (lib.imap0 (i: ({ id, ... }: [
          "${mktuntap}/bin/mktuntap"
          "-i" id
          "-p" "-v" "-B"
          (toString (interfaceFdOffset + i))
        ])) config.microvm.interfaces)
        ++
        [
          "${pkgs.crosvm}/bin/crosvm" "run"
          "-m" (toString mem)
          "-c" (toString vcpu)
          "-r" rootDisk
          "--serial" "type=stdout,console=true,stdin=true"
          "-p" "console=ttyS0 reboot=k panic=1 nomodules ${toString config.microvm.kernelParams}"
          # workarounds
          "--seccomp-log-failures"
        ]
        ++
        lib.optionals (socket != null) [
          "-s" socket
        ]
        ++
        builtins.concatMap ({ image, ... }:
          [ "--rwdisk" image ]
        ) volumes
        ++
        builtins.concatMap ({ proto, tag, source, ... }:
          let
            type = {
              "9p" = "p9";
              "virtiofs" = "fs";
            }.${proto};
          in [
            "--shared-dir" "${source}:${tag}:type=${type}"
          ]
        ) shares
        ++
        lib.concatLists (lib.imap0 (i: (_: [
          "--tap-fd" (toString (interfaceFdOffset + i))
        ])) interfaces) ++
        [ "${config.system.build.kernel.dev}/vmlinux" ]
      );

    canShutdown = false;
    shutdownCommand =
      throw "'crosvm stop' is not graceful";
  };
}
