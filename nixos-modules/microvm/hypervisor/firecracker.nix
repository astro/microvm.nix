{ config, pkgs, lib, ... }:
let
  inherit (config.microvm) vcpu mem interfaces volumes shares socket;
  rootDisk = config.system.build.squashfs;

  firectl = pkgs.firectl.overrideAttrs (_oa: {
    # allow read-only root-drive
    postPatch = ''
      substituteInPlace options.go \
          --replace "IsReadOnly:   firecracker.Bool(false)," \
          "IsReadOnly:   firecracker.Bool(true),"
      '';
    });
in {
  microvm.runner.firecracker = import ../../../pkgs/runner.nix {
    hypervisor = "firecracker";

    inherit config pkgs;

    command = lib.escapeShellArgs (
      [
        "${firectl}/bin/firectl"
        "--firecracker-binary=${pkgs.firecracker}/bin/firecracker"
        "-m" (toString mem)
        "-c" (toString vcpu)
        "--kernel=${config.system.build.kernel.dev}/vmlinux"
        "--kernel-opts=console=ttyS0 noapic reboot=k panic=1 pci=off nomodules ro quiet init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}"
        "--root-drive=${rootDisk}"
      ] ++
      (if socket != null then [ "-s" socket ] else []) ++
      map ({ image, ... }:
        "--add-drive=${image}:rw"
      ) volumes ++
      map (_:
        throw "virtiofs shares not implemented for CrosVM"
      ) shares ++
      map ({ type ? "tap", id, mac }:
        if type == "tap"
        then "--tap-device=${id}/${mac}"
        else throw "Unsupported interface type ${type} for Firecracker"
      ) interfaces
    );

    canShutdown = socket != null;

    shutdownCommand =
      if socket != null
      then lib.escapeShellArgs [
        "${pkgs.curl}/bin/curl"
        "--unix-socket" socket
        "-X" "PUT" "http://localhost/actions"
        "-H"  "Accept: application/json"
        "-H"  "Content-Type: application/json"
        "-d" (builtins.toJSON {
          action_type = "SendCtrlAltDel";
        })
      ]
      else throw "Cannot shutdown without socket";
  };
}
