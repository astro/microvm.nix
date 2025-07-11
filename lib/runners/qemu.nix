{ pkgs
, microvmConfig
, macvtapFds
}:

let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv) system;

  enableLibusb = pkg: pkg.overrideAttrs (oa: {
    configureFlags = oa.configureFlags ++ [
      "--enable-libusb"
    ];
    buildInputs = oa.buildInputs ++ (with pkgs; [
      libusb1
    ]);
  });

  minimizeQemuClosureSize = pkg: (pkg.override (oa: {
    # standin for disabling everything guilike by hand
    nixosTestRunner =
      if graphics.enable
      then oa.nixosTestRunner or false
      else true;
    enableDocs = false;
  })).overrideAttrs (oa: {
    postFixup = ''
      ${oa.postFixup or ""}
      # This particular firmware causes 192mb of closure size
      ${lib.optionalString (system != "aarch64-linux") "rm -rf $out/share/qemu/edk2-arm-*"}
    '';
  });

  overrideQemu = x: lib.pipe x (
    lib.optional requireUsb enableLibusb
    ++ lib.optional microvmConfig.optimize.enable minimizeQemuClosureSize
  );

  qemuPkg =
    if microvmConfig.cpu == null
    then
      # When cross-compiling for a target host, select qemu for the target:
      pkgs.qemu_kvm
    else
      # When cross-compiling for CPU emulation, select qemu for the host:
      pkgs.buildPackages.qemu;

  qemu = overrideQemu qemuPkg;

  inherit (microvmConfig) hostName vcpu mem balloon initialBalloonMem deflateOnOOM hotplugMem hotpluggedMem user interfaces shares socket forwardPorts devices vsock graphics storeOnDisk kernel initrdPath storeDisk credentialFiles;
  inherit (microvmConfig.qemu) machine extraArgs serialConsole;

  inherit (import ../. { inherit (pkgs) lib; }) withDriveLetters;

  volumes = withDriveLetters microvmConfig;

  requireUsb =
    graphics.enable ||
    lib.any ({ bus, ... }: bus == "usb") microvmConfig.devices;

  arch = builtins.head (builtins.split "-" system);

  cpuArgs = [
    "-cpu"
    (
      if microvmConfig.cpu != null
      then microvmConfig.cpu
      else if system == "x86_64-linux"
      # qemu crashes when sgx is used on microvm machines: https://gitlab.com/qemu-project/qemu/-/issues/2142
      then "host,+x2apic,-sgx"
      else "host"
    ) ];

  accel =
    if microvmConfig.cpu == null
    then "kvm:tcg"
    else "tcg";

  # PCI required by vfio-pci for PCI passthrough
  pciInDevices = lib.any ({ bus, ... }: bus == "pci") devices;

  requirePci =
    graphics.enable ||
    (! lib.hasPrefix "microvm" machine) ||
    shares != [] ||
    pciInDevices;

  machineOpts =
    if microvmConfig.qemu.machineOpts != null
    then microvmConfig.qemu.machineOpts
    else {
      x86_64-linux = {
        inherit accel;
        mem-merge = "on";
        acpi = "on";
      } // lib.optionalAttrs (machine == "microvm") {
        pit = "off";
        pic = "off";
        pcie = if requirePci then "on" else "off";
        usb = if requireUsb then "on" else "off";
      };
      aarch64-linux = {
        inherit accel;
        gic-version = "max";
      };
    }.${system};

  machineConfig = builtins.concatStringsSep "," (
    [ machine ] ++
    map (name:
      "${name}=${machineOpts.${name}}"
    ) (builtins.attrNames machineOpts)
  );

  devType =
    if requirePci
    then "pci"
    else "device";

  kernelPath = "${kernel.out}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";

  enumerate = n: xs:
    if xs == []
    then []
    else [
      (builtins.head xs // { index = n; })
    ] ++ (enumerate (n + 1) (builtins.tail xs));

  canSandbox =
    # Don't let qemu sandbox itself if it is going to call qemu-bridge-helper
    ! lib.any ({ type, ... }:
      type == "bridge"
    ) microvmConfig.interfaces;

  tapMultiQueue = vcpu > 1;

  forwardingOptions = lib.concatMapStrings ({ proto, from, host, guest }: {
    host = "hostfwd=${proto}:${host.address}:${toString host.port}-" +
           "${guest.address}:${toString guest.port},";
    guest = "guestfwd=${proto}:${guest.address}:${toString guest.port}-" +
            "cmd:${pkgs.netcat}/bin/nc ${host.address} ${toString host.port},";
  }.${from}) forwardPorts;

  writeQmp = data: ''
    echo '${builtins.toJSON data}'
  '';

  kernelConsole =
    if !microvmConfig.qemu.serialConsole
    then ""
    else if system == "x86_64-linux"
    then "earlyprintk=ttyS0 console=ttyS0"
    else if system == "aarch64-linux"
    then "console=ttyAMA0"
    else "";

  systemdCredentialStrings = lib.mapAttrsToList (name: path: "name=opt/io.systemd.credentials/${name},file=${path}" ) credentialFiles;
  fwCfgOptions = systemdCredentialStrings;

in
lib.warnIf (mem == 2048) ''
  QEMU hangs if memory is exactly 2GB

  <https://github.com/astro/microvm.nix/issues/171>
''
{
  inherit tapMultiQueue;

  command = if initialBalloonMem != 0
  then throw "qemu does not support initialBalloonMem"
  else if hotplugMem != 0
  then throw "qemu does not support hotplugMem"
  else if hotpluggedMem != 0
  then throw "qemu does not support hotpluggedMem"
  else lib.escapeShellArgs (
    [
      "${qemu}/bin/qemu-system-${arch}"
      "-name" hostName
      "-M" machineConfig
      "-m" (toString mem)
      "-smp" (toString vcpu)
      "-nodefaults" "-no-user-config"
      # qemu just hangs after shutdown, allow to exit by rebooting
      "-no-reboot"

      "-kernel" "${kernelPath}"
      "-initrd" initrdPath

      "-chardev" "stdio,id=stdio,signal=off"
      "-device" "virtio-rng-${devType}"
    ] ++
    lib.optionals (fwCfgOptions != [])  [
      "-fw_cfg" (lib.concatStringsSep "," fwCfgOptions)
    ] ++
    lib.optionals serialConsole [
      "-serial" "chardev:stdio"
    ] ++
    lib.optionals (microvmConfig.cpu == null) [
      "-enable-kvm"
    ] ++
    cpuArgs ++
    lib.optionals (system == "x86_64-linux") [
      "-device" "i8042"

      "-append" "${kernelConsole} reboot=t panic=-1 ${builtins.unsafeDiscardStringContext (toString microvmConfig.kernelParams)}"
    ] ++
    lib.optionals (system == "aarch64-linux") [
      "-append" "${kernelConsole} reboot=t panic=-1 ${builtins.unsafeDiscardStringContext (toString microvmConfig.kernelParams)}"
    ] ++
    lib.optionals storeOnDisk [
      "-drive" "id=store,format=raw,read-only=on,file=${storeDisk},if=none,aio=io_uring"
      "-device" "virtio-blk-${devType},drive=store${lib.optionalString (devType == "pci") ",disable-legacy=on"}"
    ] ++
    (if graphics.enable
     then [
      "-display" "gtk,gl=on"
      "-device" "virtio-vga-gl"
      "-device" "qemu-xhci"
      "-device" "usb-tablet"
      "-device" "usb-kbd"
     ]
     else [
      "-nographic"
     ]) ++
    lib.optionals canSandbox [
      "-sandbox" "on"
    ] ++
    lib.optionals (user != null) [ "-user" user ] ++
    lib.optionals (socket != null) [ "-qmp" "unix:${socket},server,nowait" ] ++
    lib.optionals balloon [
	 "-device" ("virtio-balloon,free-page-reporting=on,id=balloon0" + lib.optionalString (deflateOnOOM) ",deflate-on-oom=on")
    ] ++
    builtins.concatMap ({ image, letter, serial, direct, readOnly, ... }:
      [ "-drive"
        "id=vd${letter},format=raw,file=${image},if=none,aio=io_uring,discard=unmap${
          lib.optionalString (direct != null) ",cache=none"
        },read-only=${if readOnly then "on" else "off"}"
        "-device"
        "virtio-blk-${devType},drive=vd${letter}${
          lib.optionalString (serial != null) ",serial=${serial}"
        }"
      ]
    ) volumes ++
    lib.optionals (shares != []) (
      [
        "-object" "memory-backend-memfd,id=mem,size=${toString mem}M,share=on"
        "-numa" "node,memdev=mem"
      ] ++
      builtins.concatMap ({ proto, index, socket, source, tag, securityModel, ... }: {
        "virtiofs" = [
          "-chardev" "socket,id=fs${toString index},path=${socket}"
          "-device" "vhost-user-fs-${devType},chardev=fs${toString index},tag=${tag}"
        ];
        "9p" = [
          "-fsdev" "local,id=fs${toString index},path=${source},security_model=${securityModel}"
          "-device" "virtio-9p-${devType},fsdev=fs${toString index},mount_tag=${tag}"
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
            ]
            ++ lib.optionals (type == "user" && forwardPorts != []) [
              forwardingOptions
            ]
            ++ lib.optionals (type == "bridge") [
              "br=${bridge}" "helper=/run/wrappers/bin/qemu-bridge-helper"
            ]
            ++ lib.optionals (type == "tap") [
              "ifname=${id}"
              "script=no" "downscript=no"
            ]
            ++ lib.optionals (type == "macvtap") [ (
              let
                fds = macvtapFds.${id};
              in
                if builtins.length fds == 1
                then "fd=${toString (builtins.head fds)}"
                else "fds=${lib.concatMapStringsSep ":" toString fds}"
            ) ]
            ++ lib.optionals (type == "tap" && tapMultiQueue) [
              "queues=${toString vcpu}"
            ]
          )
        )
        "-device" "virtio-net-${devType},netdev=${id},mac=${mac}${
          # romfile= does not work with x86_64-linux and -M microvm
          # setting or -cpu different than host
          lib.optionalString (
            requirePci ||
            (microvmConfig.cpu == null && system != "x86_64-linux")
          ) ",romfile="
        }${
          lib.optionalString (tapMultiQueue && requirePci) ",mq=on,vectors=${toString (2 * vcpu + 2)}"
        }"
      ]) interfaces
    )
    ++
    lib.optionals requireUsb [
      "-device" "qemu-xhci"
    ]
    ++
    lib.optionals (vsock.cid != null) [
      "-device"
      "vhost-vsock-${devType},guest-cid=${toString vsock.cid}"
    ]
    ++
    extraArgs
  )
  + " " + # Move vfio-pci outside of
  lib.concatStringsSep " " (lib.concatMap ({ bus, path, qemu,... }: {
    pci = [
      "-device" "vfio-pci,host=${path},multifunction=on${
        # Allow to pass additional arguments to pci device
        lib.optionalString (qemu.deviceExtraArgs != null) ",${qemu.deviceExtraArgs}"
      }"
    ];
    usb = [
      "-device" "usb-host,${path}"
    ];
  }.${bus}) devices);

  canShutdown = socket != null;

  shutdownCommand =
    if socket != null
    then
      ''
        (
          ${writeQmp { execute = "qmp_capabilities"; }}
          ${writeQmp {
            execute = "input-send-event";
            arguments.events = [ {
              type = "key";
              data = {
                down = true;
                key = {
                  type = "qcode";
                  data = "ctrl";
                };
              };
            } {
              type = "key";
              data = {
                down = true;
                key = {
                  type = "qcode";
                  data = "alt";
                };
              };
            } {
              type = "key";
              data = {
                down = true;
                key = {
                  type = "qcode";
                  data = "delete";
                };
              };
            } ];
          }}
           # wait for exit
          cat
        ) | \
        ${pkgs.socat}/bin/socat STDIO UNIX:${socket},shut-none
    ''
    else throw "Cannot shutdown without socket";

  setBalloonScript =
    if socket != null
    then ''
      VALUE=$(( $SIZE * 1024 * 1024 ))
      SIZE=$( (
        ${writeQmp { execute = "qmp_capabilities"; }}
        ${writeQmp { execute = "balloon"; arguments.value = 987; }}
      ) | sed -e s/987/$VALUE/ | \
        ${pkgs.socat}/bin/socat STDIO UNIX:${socket},shut-none | \
        tail -n 1 | \
        ${pkgs.jq}/bin/jq -r .data.actual \
      )
      echo $(( $SIZE / 1024 / 1024 ))
    ''
    else null;

  requiresMacvtapAsFds = true;
}
