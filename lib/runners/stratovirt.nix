{ pkgs
, microvmConfig
, macvtapFds
}:

let
  inherit (pkgs) lib system;

  inherit (microvmConfig)
    hostName
    vcpu mem balloon initialBalloonMem hotplugMem hotpluggedMem interfaces shares socket forwardPorts devices
    kernel initrdPath
    storeOnDisk storeDisk;

  tapMultiQueue = vcpu > 1;

  inherit (import ../. { inherit (pkgs) lib; }) withDriveLetters;
  volumes = withDriveLetters microvmConfig;

  # PCI required by vfio-pci for PCI passthrough
  pciInDevices = lib.any ({ bus, ... }: bus == "pci") devices;
  requirePci = pciInDevices;
  machine = {
    x86_64-linux =
      if requirePci
      then throw "PCI configuration for stratovirt is non-functional" "q35"
      else "microvm";
    aarch64-linux = "virt";
  }.${system};

  console = {
    x86_64-linux = "ttyS0";
    aarch64-linux = "ttyAMA0";
  }.${system};

  devType = addr:
    if requirePci
    then
      if addr < 32
      then "pci,bus=pcie.0,addr=0x${pkgs.lib.toHexString addr}"
      else throw "Too big PCI addr: ${pkgs.lib.toHexString addr}"
    else "device";

  enumerate = n: xs:
    if xs == []
    then []
    else [
      (builtins.head xs // { index = n; })
    ] ++ (enumerate (n + 1) (builtins.tail xs));

  virtioblkOffset = 4;
  virtiofsOffset = virtioblkOffset + builtins.length microvmConfig.volumes;

  forwardPortsOptions =
      let
        forwardingOptions = lib.flip lib.concatMapStrings forwardPorts
          ({ proto, from, host, guest }:
            if from == "host"
              then "hostfwd=${proto}:${host.address}:${toString host.port}-" +
                   "${guest.address}:${toString guest.port},"
              else "guestfwd=${proto}:${guest.address}:${toString guest.port}-" +
                   "cmd:${pkgs.netcat}/bin/nc ${host.address} ${toString host.port},"
          );
      in
      [ forwardingOptions ];

  writeQmp = data: ''
    echo '${builtins.toJSON data}' | nc -U "${socket}"
  '';
in {
  inherit tapMultiQueue;

  command = if balloon
    then throw "balloon not implemented for stratovirt"
    else if initialBalloonMem != 0
    then throw "initialBalloonMem not implemented for stratovirt"
    else if hotplugMem != 0
    then throw "stratovirt does not support hotplugMem"
    else if hotpluggedMem != 0
    then throw "stratovirt does not support hotpluggedMem"
    else lib.escapeShellArgs (
    [
      "${pkgs.expect}/bin/unbuffer"
      "${pkgs.stratovirt}/bin/stratovirt"
      "-name" hostName
      "-machine" machine
      "-m" (toString mem)
      "-smp" (toString vcpu)

      "-kernel" "${kernel}/bzImage"
      "-initrd" initrdPath
      "-append" "console=${console} edd=off reboot=t panic=-1 verbose ${builtins.unsafeDiscardStringContext (toString microvmConfig.kernelParams)}"

      "-serial" "stdio"
      "-object" "rng-random,id=rng,filename=/dev/random"
      "-device" "virtio-rng-${devType 1},rng=rng,id=rng_dev"
    ] ++
    lib.optionals storeOnDisk [
      "-drive" "id=store,format=raw,readonly=on,file=${storeDisk},if=none,aio=io_uring,direct=false"
      "-device" "virtio-blk-${devType 2},drive=store,id=blk_store"
    ] ++
    lib.optionals (socket != null) [ "-qmp" "unix:${socket},server,nowait" ] ++
    builtins.concatMap ({ index, image, letter, serial, direct, readOnly, ... }: [
      "-drive"
      "id=vd${
        letter
      },format=raw,if=none,aio=io_uring,file=${
        image
      },direct=${
        if direct then "on" else "off"
      },readonly=${
        if readOnly then "on" else "off"
      }"
      "-device"
      "virtio-blk-${
        devType (virtioblkOffset + index)
      },drive=vd${
        letter
      },id=blk_vd${
        letter
      }${
        lib.optionalString (serial != null) ",serial=${serial}"
      }"
    ]) (enumerate 0 volumes) ++
    lib.optionals (shares != []) (
      builtins.concatMap ({ proto, index, socket, source, tag, ... }: {
        "virtiofs" = [
          "-chardev"
          "socket,id=fs${toString index},path=${socket}"
          "-device"
          "vhost-user-fs-${devType (virtiofsOffset + index)},chardev=fs${toString index},tag=${tag},id=fs${toString index}"
        ];
      }.${proto}) (enumerate 0 shares)
    )
    ++
    lib.warnIf (
      forwardPorts != [] &&
      ! builtins.any ({ type, ... }: type == "user") interfaces
    ) "${hostName}: forwardPortsOptions only running with user network" (
      builtins.concatMap ({ type, id, mac, bridge, ... }: [
        "-netdev" (
          lib.concatStringsSep "," (
            [
              (if type == "macvtap" then "tap" else "${type}")
              "id=${id}"
              "queues=${toString (lib.min 16 vcpu)}"
            ]
            ++ lib.optionals (type == "user" && forwardPortsOptions != []) forwardPortsOptions
            ++ lib.optionals (type == "bridge") [
              "br=${bridge}" "helper=/run/wrappers/bin/qemu-bridge-helper"
            ]
            ++ lib.optionals (type == "tap") [
              "ifname=${id}"
            ]
            ++ lib.optionals (type == "macvtap") [
              "fd=${toString macvtapFds.${id}}"
            ]
            ++ lib.optionals tapMultiQueue [
              "queues=${toString vcpu}"
            ]
          )
        )
        # TODO: devType (0x10 + i)
        "-device" (
          lib.concatStringsSep "," [
            "virtio-net-${devType 30}"
            "id=net_${id}"
            "netdev=${id}"
            "mac=${mac}"
            "mq=${if tapMultiQueue then "on" else "off"}"
          ]
        )
      ]) interfaces
    )
    ++
    builtins.concatMap ({ bus, path, ... }: {
      pci = [
        "-device" "vfio-pci,host=${path}"
      ];
      usb = [
        "-device" "usb-host,${path}"
      ];
    }.${bus}) devices
    ++
    lib.optionals (lib.hasPrefix "q35" machine) [
      "-drive" "file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd,if=pflash,unit=0,readonly=true"
      "-drive" "file=${pkgs.OVMF.fd}/FV/OVMF_VARS.fd,if=pflash,unit=1,readonly=true"
    ]
  );

  # Not supported for the `microvm` machine model
  canShutdown = false;

  shutdownCommand =
    if socket != null
    then
      ''
        # ${writeQmp { execute = "qmp_capabilities"; }}
        # ${writeQmp { execute = "system_powerdown"; }}
        ${writeQmp {
          execute = "input_event";
          arguments = {
            key = "keyboard";
            value = "ctrl, 1";
          };
        }}
        ${writeQmp {
          execute = "input_event";
          arguments = {
            key = "keyboard";
            value = "alt, 1";
          };
        }}
        ${writeQmp {
          execute = "input_event";
          arguments = {
            key = "keyboard";
            value = "delete, 1";
          };
        }}
        # wait for exit
        cat "${socket}"
      ''
    else throw "Cannot shutdown without socket";

  requiresMacvtapAsFds = true;
}
