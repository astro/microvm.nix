{ pkgs
, microvmConfig
, ...
}:

let
  inherit (pkgs) lib;
  inherit (microvmConfig)
    hostName preStart user
    vcpu mem balloon initialBalloonMem hotplugMem hotpluggedMem interfaces volumes shares devices vsock
    kernel initrdPath
    storeDisk storeOnDisk;
in {
  preStart = ''
    ${preStart}
    export HOME=$PWD
  '';

  command =
    if user != null
    then throw "kvmtool will not change user"
    else if initialBalloonMem != 0
    then throw "kvmtool does not support initialBalloonMem"
    else if hotplugMem != 0
    then throw "kvmtool does not support hotplugMem"
    else if hotpluggedMem != 0
    then throw "kvmtool does not support hotpluggedMem"
    else builtins.concatStringsSep " " (
      [
        "${pkgs.kvmtool}/bin/lkvm" "run"
        "--name" (lib.escapeShellArg hostName)
        "-m" (toString mem)
        "-c" (toString vcpu)
        "--console" "serial"
        "--rng"
        "-k" (lib.escapeShellArg "${kernel}/${pkgs.stdenv.hostPlatform.linux-kernel.target}")
        "-i" initrdPath
        "-p" (lib.escapeShellArg "console=ttyS0 reboot=k panic=1 ${builtins.unsafeDiscardStringContext (toString microvmConfig.kernelParams)}")
      ]
      ++
      lib.optionals storeOnDisk [
        "-d" (lib.escapeShellArg "${storeDisk},ro")
      ]
      ++
      lib.optionals balloon [ "--balloon" ]
      ++
      builtins.concatMap ({ serial, direct, readOnly, ... }:
        lib.warnIf (serial != null) ''
          Volume serial is not supported for kvmtool
        ''
        [ "-d"
          (lib.escapeShellArg "image${
            lib.optionalString direct ",direct"
          }${
            lib.optionalString readOnly ",ro"
          }")
        ]
      ) volumes
      ++
      builtins.concatMap ({ proto, source, tag, ... }:
        if proto == "9p"
        then [
          "--9p" (lib.escapeShellArg "${source},${tag}")
        ] else throw "virtiofs shares not implemented for kvmtool"
      ) shares
      ++
      builtins.concatMap ({ type, id, mac, ... }:
        if builtins.elem type [ "user" "tap" ]
        then [
          "-n" (lib.escapeShellArg "mode=${type},tapif=${id},guest_mac=${mac}")
        ]
        else if type == "macvtap"
        then [
          "-n" "mode=tap,tapif=/dev/tap$(< /sys/class/net/${id}/ifindex),guest_mac=${mac}"
        ]
        else throw "interface type ${type} is not supported by kvmtool"
      ) interfaces
      ++
      map ({ bus, path }: {
        pci = lib.escapeShellArg "--vfio-pci=${path}";
        usb = throw "USB passthrough is not supported on kvmtool";
      }.${bus}) devices
      ++
      lib.optionals (vsock.cid != null) [
        "--vsock" (toString vsock.cid)
      ]
    );

  # `lkvm stop` works but is not graceful.
  canShutdown = false;

  setBalloonScript = ''
    if [[ $SIZE =~ ^-(\d+)$ ]]; then
      ARGS="-d ''${BASH_REMATCH[1]}"
    else
      ARGS="-i $SIZE"
    fi
    HOME=$PWD ${pkgs.kvmtool}/bin/lkvm balloon $ARGS -n ${hostName}
  '';
}
