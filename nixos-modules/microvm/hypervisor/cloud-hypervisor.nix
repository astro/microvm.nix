{ config, pkgs, lib, ... }:
let
  inherit (config.microvm) vcpu mem user interfaces volumes shares socket;
  rootDisk = config.system.build.squashfs;
in {
  microvm.runner.cloud-hypervisor = import ../../../pkgs/runner.nix {
    hypervisor = "cloud-hypervisor";

    inherit config pkgs;

    preStart = ''
      ${config.microvm.preStart}
      ${lib.optionalString (socket != null) ''
        # workaround cloud-hypervisor sometimes
        # stumbling over a preexisting socket
        rm -f '${socket}'
      ''}
    '';

    command =
      if user != null
      then throw "cloud-hypervisor will not change user"
      else lib.escapeShellArgs (
        [
          "${pkgs.cloud-hypervisor}/bin/cloud-hypervisor"
          "--memory" "size=${toString mem}M,mergeable=on,shared=on"
          "--cpus" "boot=${toString vcpu}"
          "--watchdog"
          "--console" "tty"
          "--kernel" "${config.system.build.kernel.dev}/vmlinux"
          "--cmdline" "console=hvc0 reboot=t panic=-1 ${toString config.microvm.kernelParams}"
          "--seccomp" "true"
          "--disk" "path=${rootDisk},readonly=on"
        ]
        ++
        map ({ image, ... }:
          "path=${image}"
        ) volumes
        ++
        lib.optionals (shares != []) (
          [ "--fs" ] ++
          map ({ proto, socket, tag, ... }:
            if proto == "virtiofs"
            then "tag=${tag},socket=${socket}"
            else throw "cloud-hypervisor supports only shares that are virtiofs"
          ) shares
        )
        ++
        lib.optionals (socket != null) [ "--api-socket" socket ]
        ++
        lib.optionals (interfaces != []) (
          [ "--net" ] ++
          map ({ type, id, mac, ... }:
            if type == "tap"
            then "tap=${id},mac=${mac}"
            else throw "Unsupported interface type ${type} for Cloud-Hypervisor"
          ) interfaces
        )
      );

    canShutdown = socket != null;

    shutdownCommand =
      if socket != null
      then ''
        api() {
          ${pkgs.curl}/bin/curl \
            --unix-socket ${socket} \
            $@
        }

        api -X PUT http://localhost/api/v1/vm.power-button

        # wait for exit
        while api http://localhost/api/v1/vm.info 2>/dev/null ; do
          sleep 0.1
        done
      ''
      else throw "Cannot shutdown without socket";
  };
}
