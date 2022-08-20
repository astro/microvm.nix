{ pkgs
, microvmConfig
, kernel
, bootDisk
}:

let
  inherit (pkgs) lib;
  inherit (microvmConfig) vcpu mem user interfaces volumes shares socket devices;
  mktuntap = pkgs.callPackage ../../pkgs/mktuntap.nix {};
  interfaceFdOffset = 3;
in {
  command =
    if user != null
    then throw "crosvm will not change user"
    else lib.escapeShellArgs (
      lib.concatLists (lib.imap0 (i: ({ id, ... }: [
        "${mktuntap}/bin/mktuntap"
        "-i" id
        "-p" "-v" "-B"
        (toString (interfaceFdOffset + i))
      ])) microvmConfig.interfaces)
      ++
      [
        "${pkgs.crosvm}/bin/crosvm" "run"
        "-m" (toString mem)
        "-c" (toString vcpu)
        "-r" bootDisk
        "--serial" "type=stdout,console=true,stdin=true"
        "-p" "console=ttyS0 reboot=k panic=1 ${toString microvmConfig.kernelParams}"
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
      ])) interfaces)
      ++
      builtins.concatMap ({ bus, path }: {
        pci = [ "--vfio" "/sys/bus/pci/devices/${path},iommu=viommu" ];
        usb = throw "USB passthrough is not supported on crosvm";
      }.${bus}) devices
      ++
      [ "${kernel.dev}/vmlinux" ]
    );

  canShutdown = socket != null;

  shutdownCommand =
    if socket != null
    then ''
        ${pkgs.crosvm}/bin/crosvm powerbtn ${socket}
      ''
    else throw "Cannot shutdown without socket";
}
