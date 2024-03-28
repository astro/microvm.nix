{ pkgs
, microvmConfig
, macvtapFds
}:

let
  inherit (pkgs) lib system;
  inherit (microvmConfig)
    hostName user socket preStart
    vcpu mem
    interfaces volumes shares devices
    kernel initrdPath
    storeDisk;

  kernelPath = {
    x86_64-linux = "${kernel.dev}/vmlinux";
    aarch64-linux = "${kernel.out}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";
  }.${system};

  # Firecracker config, as JSON in `configFile`
  config = {
    boot-source = {
      kernel_image_path = kernelPath;
      initrd_path = initrdPath;
      boot_args = "console=ttyS0 noapic reboot=k panic=1 pci=off i8042.noaux i8042.nomux i8042.nopnp i8042.dumbkbd ${toString microvmConfig.kernelParams}";
    };
    machine-config = {
      vcpu_count = vcpu;
      mem_size_mib = mem;
      # Without this, starting of firecracker fails with an error message:
      # Enabling simultaneous multithreading is not supported on aarch64
      smt = system != "aarch64-linux";
      # Run even on old CPUs
      cpu_template = null;
    };
    drives = [ {
      drive_id = "store";
      path_on_host = storeDisk;
      is_root_device = false;
      is_read_only = true;
      io_engine = "Async";
    } ] ++ map ({ image, ... }: {
      drive_id = image;
      path_on_host = image;
      is_root_device = false;
      is_read_only = false;
      io_engine = "Async";
    }) volumes;
    network-interfaces = map ({ type, id, mac, ... }:
      if type == "tap"
      then {
        iface_id = id;
        host_dev_name = id;
        guest_mac = mac;
      }
      else throw "Network interface type ${type} not implemented for Firecracker"
    ) interfaces;
    vsock = null;
  };

  configFile = pkgs.writeText "firecracker-${hostName}.json" (
    builtins.toJSON config
  );

in {
  command =
    if user != null
    then throw "firecracker will not change user"
    else if shares != []
    then throw "9p/virtiofs shares not implemented for Firecracker"
    else if devices != []
    then throw "devices passthrough not implemented for Firecracker"
    else lib.escapeShellArgs [
      "${pkgs.firecracker}/bin/firecracker"
      "--config-file" configFile
      "--api-sock" (
        if socket != null
        then socket
        else throw "Firecracker must be configured with an API socket (option microvm.socket)!"
      )
    ];

  preStart = ''
    ${preStart}

    if [ -e '${socket}' ]; then
      mv '${socket}' '${socket}.old'
    fi
  '';

  canShutdown = socket != null;

  shutdownCommand =
    if socket != null
    then ''
      ${pkgs.curl}/bin/curl -s \
        --unix-socket ${socket} \
        -X PUT http://localhost/actions \
        -d '{ "action_type": "SendCtrlAltDel" }'

      # wait for exit
      ${pkgs.socat}/bin/socat STDOUT UNIX:${socket},shut-none
    ''
    else throw "Cannot shutdown without socket";
}
