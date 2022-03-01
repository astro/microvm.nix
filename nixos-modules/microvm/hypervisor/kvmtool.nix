{ config, pkgs, lib, ... }:
let
  inherit (config.microvm) vcpu mem user interfaces volumes shares preStart;
  rootDisk = config.system.build.squashfs;
in {
  microvm.runner.kvmtool = import ../../../pkgs/runner.nix {
    hypervisor = "kvmtool";

    inherit config pkgs;

    preStart = ''
      ${preStart}
      export HOME=$PWD
    '';

    command =
      if user != null
      then throw "kvmtool will not change user"
      else lib.escapeShellArgs (
        [
          "${pkgs.kvmtool}/bin/lkvm" "run"
          "--name" config.networking.hostName
          "-m" (toString mem)
          "-c" (toString vcpu)
          "-d" "${rootDisk},ro"
          "--console" "virtio"
          "--rng"
          "-k" "${config.system.build.kernel}/bzImage"
          "-p" "console=hvc0 reboot=k panic=1 nomodules ${toString config.microvm.kernelParams}"
        ] ++
        builtins.concatMap ({ image, ... }:
          [ "-d" image ]
        ) volumes ++
        builtins.concatMap ({ proto, source, tag, ... }:
          if proto == "9p"
          then [
            "--9p" "${source},${tag}"
          ] else throw "virtiofs shares not implemented for kvmtool"
        ) shares ++
        builtins.concatMap ({ type, id, mac, ... }:
          if builtins.elem type [ "user" "tap" ]
          then [
            "-n" "mode=${type},tapif=${id},guest_mac=${mac}"
          ] else throw "interface type ${type} is not supported by kvmtool"
        ) interfaces
      );

    # `lkvm stop` works but is not graceful.
    canShutdown = false;
  };
}
