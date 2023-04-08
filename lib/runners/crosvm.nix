{ pkgs
, microvmConfig
, kernel
, bootDisk
}:

let
  inherit (pkgs) lib system;
  inherit (microvmConfig) vcpu mem balloonMem user interfaces volumes shares socket devices;
  inherit (microvmConfig.crosvm) pivotRoot extraArgs;
  mktuntap = pkgs.callPackage ../../pkgs/mktuntap.nix {};
  interfaceFdOffset = 3;
  kernelPath = {
    x86_64-linux = "${kernel.dev}/vmlinux";
    aarch64-linux = "${kernel.out}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";
  }.${system};
in {
  preStart = ''
    rm -f ${socket}
    ${microvmConfig.preStart}
    ${lib.optionalString (pivotRoot != null) ''
      mkdir -p ${pivotRoot}
    ''}
  '';

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
        "-m" (toString (mem + balloonMem))
        "-c" (toString vcpu)
        "-r" bootDisk
        "--serial" "type=stdout,console=true,stdin=true"
        "-p" "console=ttyS0 reboot=k panic=1 ${toString microvmConfig.kernelParams}"
      ]
      ++
      lib.optionals (builtins.compareVersions pkgs.crosvm.version "107.1" < 0) [
        # workarounds
        "--seccomp-log-failures"
      ]
      ++
      lib.optionals (pivotRoot != null) [
        "--pivot-root"
        pivotRoot
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
      [ "${kernelPath}" ]
      ++
      extraArgs
    );

  canShutdown = socket != null;

  shutdownCommand =
    if socket != null
    then ''
        ${pkgs.crosvm}/bin/crosvm powerbtn ${socket}
      ''
    else throw "Cannot shutdown without socket";

  setBalloonScript =
    if socket != null
    then ''
      VALUE=$(( $SIZE * 1024 * 1024 ))
      ${pkgs.crosvm}/bin/crosvm balloon $VALUE ${socket}
      SIZE=$( ${pkgs.crosvm}/bin/crosvm balloon_stats ${socket} | \
        ${pkgs.jq}/bin/jq -r .BalloonStats.balloon_actual \
      )
      echo $(( $SIZE / 1024 / 1024 ))
    ''
    else null;
}
