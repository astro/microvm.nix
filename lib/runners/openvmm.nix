{ pkgs
, microvmConfig
, macvtapFds
}:

let
  inherit (pkgs) lib;
  inherit (microvmConfig)
    user
    vcpu mem interfaces volumes shares devices vsock
    kernel initrdPath
    storeDisk storeOnDisk;
in {
  command =
    if user != null
    then throw "openvmm will not change user"
    else builtins.concatStringsSep " " (
      [
        "${pkgs.openvmm}/bin/openvmm"
        "-m" "${toString mem}M"
        "-p" (toString vcpu)
        "-k" (lib.escapeShellArg "${kernel.dev}/vmlinux")
        "-r" initrdPath
        "-c" (lib.escapeShellArg "console=ttyS0 reboot=k panic=1 verbose ${toString microvmConfig.kernelParams}")
        # "--vmbus-redirect"
        "--hv"
        # "--virtio-console"
        "--virtio-serial" "stderr"
        "--guest-watchdog"
      ]
      ++
      lib.optionals storeOnDisk [
        "--disk" (lib.escapeShellArg "file:${storeDisk},ro")
      ]
      ++
      builtins.concatMap ({ image, ... }:
        [ "--disk" (lib.escapeShellArg "file:${image},uh") ]
      ) volumes
      ++
      builtins.concatMap ({ proto, source, tag, ... }:
        {
          virtiofs = [
            "--virtio-fs" (lib.escapeShellArg "${tag}:${source}")
          ];
          "9p" = [
            "--virtio-9p" (lib.escapeShellArg "${tag}:${source}")
          ];
        }.${proto}
      ) shares
      ++
      builtins.concatMap ({ type, id, mac, ... }:
        if type == "tap"
        then [
          "--virtio-net" "tap"
        ]
          # TODO: --nic
        else throw "interface type ${type} is not supported by openvmm"
      ) interfaces
      ++
      map ({ ... }:
        throw "PCI/USB passthrough is not supported on openvmm"
      ) devices
      ++ (
        if vsock.cid != null
        then throw "Host-native AF_VSOCK is not supported by openvmm"
        else []
      )
    );

  # TODO:
  canShutdown = false;
}
