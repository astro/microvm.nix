{ config, pkgs, lib, ... }:
let
  inherit (config.microvm) vcpu mem user interfaces volumes shares socket;
  rootDisk = config.system.build.squashfs;
in {
  microvm.runner.cloud-hypervisor = import ../../../pkgs/runner.nix {
    hypervisor = "cloud-hypervisor";

    inherit config pkgs;

    command = lib.escapeShellArgs (
      assert user == null;
      [
        "${pkgs.cloud-hypervisor}/bin/cloud-hypervisor"
        "--memory" "size=${toString mem}M,mergeable=on,shared=on"
        "--cpus" "boot=${toString vcpu}"
        "--rng" "--watchdog"
        "--console" "tty"
        "--kernel" "${config.system.build.kernel.dev}/vmlinux"
        "--cmdline" "console=hvc0 quiet reboot=t panic=-1 ro root=/dev/vda init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}"
        "--seccomp" "true"
        "--disk" "path=${rootDisk},readonly=on"
      ] ++
      map ({ image, ... }:
        "path=${image}"
      ) volumes ++
      (if shares != []
       then [ "--fs" ] ++
            (map ({ socket, tag, ... }:
              "tag=${tag},socket=${socket}"
            ) shares)
       else []) ++
      (if socket != null
       then [ "--api-socket" socket ]
       else []) ++
      (if interfaces != []
       then [ "--net" ] ++
            (map ({ type ? "tap", id, mac }:
              if type == "tap"
              then "tap=${id},mac=${mac}"
              else throw "Unsupported interface type ${type} for Cloud-Hypervisor"
            ) interfaces)
       else [])
    );

    canShutdown = socket != null;

    shutdownCommand =
      if socket != null
      then lib.escapeShellArgs [
        "${pkgs.curl}/bin/curl"
        "--unix-socket" socket
        "-X" "PUT" "http://localhost/api/v1/vm.power-button"
      ]
      else throw "Cannot shutdown without socket";
  };
}
