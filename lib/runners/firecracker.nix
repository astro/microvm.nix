{ pkgs
, microvmConfig
, kernel
, bootDisk
}:

let
  inherit (pkgs) lib system;
  inherit (microvmConfig) vcpu mem user interfaces volumes shares socket devices;
  kernelPath = {
    x86_64-linux = "${kernel.dev}/vmlinux";
    aarch64-linux = "${kernel.out}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";
  }.${system};
in {
  command =
    if user != null
    then throw "firecracker will not change user"
    else lib.escapeShellArgs (
      [
        "${pkgs.firectl}/bin/firectl"
        "--firecracker-binary=${pkgs.firecracker}/bin/firecracker"
        "-m" (toString mem)
        "-c" (toString vcpu)
        "--kernel=${kernelPath}"
        "--kernel-opts=console=ttyS0 noapic reboot=k panic=1 pci=off i8042.noaux i8042.nomux i8042.nopnp i8042.dumbkbd ${toString microvmConfig.kernelParams}"
        "--root-drive=${bootDisk}:ro"
      ]
      ++
      lib.optionals (socket != null) [ "-s" socket ]
      ++
      map ({ image, ... }:
        "--add-drive=${image}:rw"
      ) volumes
      ++
      map (_:
        throw "9p/virtiofs shares not implemented for Firecracker"
      ) shares
      ++
      map ({ type, id, mac, ... }:
        if type == "tap"
        then "--tap-device=${id}/${mac}"
        else throw "Unsupported interface type ${type} for Firecracker"
      ) interfaces
      ++
      map (_:
        throw "devices passthrough is not implemented for Firecracker"
      ) devices
    );

  canShutdown = socket != null;

  shutdownCommand =
    if socket != null
    then ''
      ${pkgs.curl}/bin/curl \
        --unix-socket ${socket} \
        -X PUT http://localhost/actions \
        -d '{ "action_type": "SendCtrlAltDel" }'

      # wait for exit
      ${pkgs.socat}/bin/socat STDOUT UNIX:${socket},shut-none
    ''
    else throw "Cannot shutdown without socket";
}
