{ pkgs
, microvmConfig
, macvtapFds
, ...
}:

let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv) system;
  inherit (microvmConfig)
    vcpu mem balloon initialBalloonMem hotplugMem hotpluggedMem user volumes shares
    socket devices vsock graphics
    kernel initrdPath storeDisk storeOnDisk;
  inherit (microvmConfig.crosvm) pivotRoot extraArgs;

  kernelPath = {
    x86_64-linux = "${kernel.dev}/vmlinux";
    aarch64-linux = "${kernel.out}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";
  }.${system};

  gpuParams = {
    context-types = "virgl:virgl2:cross-domain";
    egl = true;
    vulkan = true;
  };

in {

  preStart = ''
    rm -f ${socket}
    ${microvmConfig.preStart}
    ${lib.optionalString (pivotRoot != null) ''
      mkdir -p ${pivotRoot}
    ''}
  '' + lib.optionalString graphics.enable ''
    rm -f ${graphics.socket}
    ${pkgs.crosvm}/bin/crosvm device gpu \
      --socket ${graphics.socket} \
      --wayland-sock $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY\
      --params '${builtins.toJSON gpuParams}' \
      &
    while ! [ -S ${graphics.socket} ]; do
      sleep .1
    done
  '';

  command =
    if user != null
    then throw "crosvm will not change user"
    else if initialBalloonMem != 0
    then throw "crosvm does not support initialBalloonMem"
    else if hotplugMem != 0
    then throw "crosvm does not support hotplugMem"
    else if hotpluggedMem != 0
    then throw "crosvm does not support hotpluggedMem"
    else lib.escapeShellArgs (
      [
        "${pkgs.crosvm}/bin/crosvm" "run"
        "-m" (toString mem)
        "-c" (toString vcpu)
        "--serial" "type=stdout,console=true,stdin=true"
        "-p" "console=ttyS0 reboot=k panic=1 ${builtins.unsafeDiscardStringContext (toString microvmConfig.kernelParams)}"
      ]
      ++
      lib.optional (!balloon) "--no-balloon"
      ++
      lib.optionals storeOnDisk [
        "-r" storeDisk
      ]
      ++
      lib.optionals graphics.enable [
        "--vhost-user-gpu" graphics.socket
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
      builtins.concatMap ({ image, direct, serial, readOnly, ... }:
        [ "--block"
          "${image},o_direct=${
            lib.boolToString direct
          },ro=${
            lib.boolToString readOnly
          }${
            lib.optionalString (serial != null) ",id=${serial}"
          }"
        ]
      ) volumes
      ++
      builtins.concatMap ({ proto, tag, source, socket, ... }: {
        "virtiofs" = [
          "--vhost-user" "type=fs,socket=${socket}"
        ];
        "9p" = [
          "--shared-dir" "${source}:${tag}:type=p9"
        ];
      }.${proto}) shares
      ++
      (builtins.concatMap ({ id, type, mac, ... }: [
        "--net"
        (lib.concatStringsSep "," ([
          ( if type == "tap"
            then "tap-name=${id}"
            else if type == "macvtap"
            then "tap-fd=${toString macvtapFds.${id}}"
            else throw "Unsupported interface type ${type} for crosvm"
          )
          "mac=${mac}"
        # ] ++ lib.optionals (vcpu > 1) [
        #   "vq-pairs=${toString vcpu}"
        ]))
      ]) microvmConfig.interfaces)
      # ++
      # lib.optionals (vcpu > 1) [
      #   "--net-vq-pairs" (toString vcpu)
      # ]
      ++
      lib.optionals (vsock.cid != null) [
        "--vsock" (toString vsock.cid)
      ]
      ++
      [
        "--initrd" initrdPath
        kernelPath
      ]
    )
    + " " + # Move vfio-pci outside of
      lib.concatStringsSep " " (lib.concatMap ({ bus, path, ... }: {
        pci = [ "--vfio" "/sys/bus/pci/devices/${path},iommu=viommu" ];
        usb = throw "USB passthrough is not supported on crosvm";
      }.${bus}) devices)
    + " " + lib.escapeShellArgs extraArgs;

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

  requiresMacvtapAsFds = true;
}
