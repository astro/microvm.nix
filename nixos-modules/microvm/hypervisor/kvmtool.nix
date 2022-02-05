{ config, pkgs, lib, ... }:
let
  inherit (config.microvm) vcpu mem interfaces volumes shares preStart;
  rootDisk = config.system.build.squashfs;
in {
  microvm.runner.kvmtool = import ../../../pkgs/runner.nix {
    hypervisor = "kvmtool";

    inherit config pkgs;

    preStart = ''
      ${preStart}
      export HOME=$PWD
    '';

    command = lib.escapeShellArgs (
      [
        "${pkgs.kvmtool}/bin/lkvm" "run"
        "--name" config.networking.hostName
        "-m" (toString mem)
        "-c" (toString vcpu)
        "-d" "${rootDisk},ro"
        "--console" "virtio"
        "--rng"
        "-k" "${config.system.build.kernel}/bzImage"
        "-p" "console=ttyS0 quiet reboot=k panic=1 nomodules ro init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}"
      ] ++
      builtins.concatMap ({ image, ... }:
        [ "-d" image ]
      ) volumes ++
      # TODO:
      map (_:
        throw "virtiofs shares not implemented for kvmtool"
      ) shares ++
      builtins.concatMap ({ type, id, mac, ... }:
        [ "-n" "mode=${type},tapif=${id},guest_mac=${mac}" ]
      ) interfaces
    );

    # `lkvm stop` works but is not graceful.
    canShutdown = false;
  };
}
