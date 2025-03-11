{ config, lib, pkgs, ... }:
let
  self-lib = import ../../lib {
    inherit lib;
  };

  hostName = config.networking.hostName or "$HOSTNAME";
  kernelAtLeast = lib.versionAtLeast config.boot.kernelPackages.kernel.version;
in
{
  options.microvm = with lib; {
    guest.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable the microvm.nix guest module at all.
      '';
    };

    optimize.enable = lib.mkOption {
      description = ''
        Enables some optimizations by default to closure size and startup time:
          - defaults documentation to off
          - defaults to using systemd in initrd
          - use systemd-networkd
          - disables systemd-network-wait-online
          - disables NixOS system switching if the host store is not mounted

        This takes a few hundred MB off the closure size, including qemu,
        allowing for putting MicroVMs inside Docker containers.
      '';

      type = lib.types.bool;
      default = true;
    };

    cpu = mkOption {
      type = with types; nullOr str;
      default = null;
      description = ''
        What CPU to emulate, if any. If different from the host
        architecture, it will have a serious performance hit.

        ::: {.note}
        Only supported with qemu.
        :::
      '';
    };

    hypervisor = mkOption {
      type = types.enum self-lib.hypervisors;
      default = "qemu";
      description = ''
        Which hypervisor to use for this MicroVM

        Choose one of: ${lib.concatStringsSep ", " self-lib.hypervisors}
      '';
    };

    preStart = mkOption {
      description = "Commands to run before starting the hypervisor";
      default = "";
      type = types.lines;
    };

    socket = mkOption {
      description = "Hypervisor control socket path";
      default = "${hostName}.sock";
      defaultText = literalExpression ''"''${hostName}.sock"'';
      type = with types; nullOr str;
    };

    user = mkOption {
      description = "User to switch to when started as root";
      default = null;
      type = with types; nullOr str;
    };

    kernel = mkOption {
      description = "Kernel package to use for MicroVM runners. Better set `boot.kernelPackages` instead.";
      default = config.boot.kernelPackages.kernel;
      defaultText = literalExpression ''"''${config.boot.kernelPackages.kernel}"'';
      type = types.package;
    };

    initrdPath = mkOption {
      description = "Path to the initrd file in the initrd package";
      default = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
      defaultText = literalExpression ''"''${config.system.build.initialRamdisk}/''${config.system.boot.loader.initrdFile}"'';
      type = types.path;
    };

    vcpu = mkOption {
      description = "Number of virtual CPU cores";
      default = 1;
      type = types.int;
    };

    mem = mkOption {
      description = "Amount of RAM in megabytes";
      default = 512;
      type = types.int;
    };

    hugepageMem = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to use hugepages as memory backend.
        (Currently only respected if using cloud-hypervisor)
      '';
    };

    balloonMem = mkOption {
      description = ''
        Amount of balloon memory in megabytes

        The way virtio-balloon works is that this is the memory size
        that the host can request to be freed by the VM. Initial
        booting of the VM allocates mem+balloonMem megabytes of RAM.
      '';
      default = 0;
      type = types.int;
    };

    deflateOnOOM = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable automatic balloon deflation on out-of-memory.
      '';
    };


    forwardPorts = mkOption {
      type = types.listOf
        (types.submodule {
          options.from = mkOption {
            type = types.enum [ "host" "guest" ];
            default = "host";
            description =
              ''
                Controls the direction in which the ports are mapped:

                - <literal>"host"</literal> means traffic from the host ports
                is forwarded to the given guest port.

                - <literal>"guest"</literal> means traffic from the guest ports
                is forwarded to the given host port.
              '';
          };
          options.proto = mkOption {
            type = types.enum [ "tcp" "udp" ];
            default = "tcp";
            description = "The protocol to forward.";
          };
          options.host.address = mkOption {
            type = types.str;
            default = "";
            description = "The IPv4 address of the host.";
          };
          options.host.port = mkOption {
            type = types.port;
            description = "The host port to be mapped.";
          };
          options.guest.address = mkOption {
            type = types.str;
            default = "";
            description = "The IPv4 address on the guest VLAN.";
          };
          options.guest.port = mkOption {
            type = types.port;
            description = "The guest port to be mapped.";
          };
        });
      default = [];
      example = lib.literalExpression /* nix */ ''
        [ # forward local port 2222 -> 22, to ssh into the VM
          { from = "host"; host.port = 2222; guest.port = 22; }

          # forward local port 80 -> 10.0.2.10:80 in the VLAN
          { from = "guest";
            guest.address = "10.0.2.10"; guest.port = 80;
            host.address = "127.0.0.1"; host.port = 80;
          }
        ]
      '';
      description =
        ''
          When using the SLiRP user networking (default), this option allows to
          forward ports to/from the host/guest.

          ::: {.warning}
          If the NixOS firewall on the virtual machine is enabled, you
          also have to open the guest ports to enable the traffic
          between host and guest.
          :::

          ::: {.note}
          Currently QEMU supports only IPv4 forwarding.
          :::
        '';
    };

    volumes = mkOption {
      description = "Disk images";
      default = [];
      type = with types; listOf (submodule {
        options = {
          image = mkOption {
            type = str;
            description = "Path to disk image on the host";
          };
          serial = mkOption {
            type = nullOr str;
            default = null;
            description = "User-configured serial number for the disk";
          };
          direct = mkOption {
            type = bool;
            default = false;
            description = "Whether to set O_DIRECT on the disk.";
          };
          readOnly = mkOption {
            type = bool;
            default = false;
            description = "Turn off write access";
          };
          label = mkOption {
            type = nullOr str;
            default = null;
            description = "Label of the volume, if any. Only applicable if `autoCreate` is true; otherwise labeling of the volume must be done manually";
          };
          mountPoint = mkOption {
            type = nullOr path;
            description = "If and where to mount the volume inside the container";
          };
          size = mkOption {
            type = int;
            description = "Volume size if created automatically";
          };
          autoCreate = mkOption {
            type = bool;
            default = true;
            description = "Created image on host automatically before start?";
          };
          mkfsExtraArgs = mkOption {
            type = listOf str;
            default = [];
            description = "Set extra Filesystem creation parameters";
          };
          fsType = mkOption {
            type = str;
            default = "ext4";
            description = "Filesystem for automatic creation and mounting";
          };
        };
      });
    };

    interfaces = mkOption {
      description = "Network interfaces";
      default = [];
      type = with types; listOf (submodule {
        options = {
          type = mkOption {
            type = enum [ "user" "tap" "macvtap" "bridge" ];
            description = ''
              Interface type
            '';
          };
          id = mkOption {
            type = str;
            description = ''
              Interface name on the host
            '';
          };
          macvtap.link = mkOption {
            type = str;
            description = ''
              Attach network interface to host interface for type = "macvlan"
            '';
          };
          macvtap.mode = mkOption {
            type = enum ["private" "vepa" "bridge" "passthru" "source"];
            description = ''
              The MACVLAN mode to use
            '';
          };
          bridge = mkOption {
            type = nullOr str;
            default = null;
            description = ''
              Attach network interface to host bridge interface for type = "bridge"
            '';
          };
          mac = mkOption {
            type = str;
            description = ''
              MAC address of the guest's network interface
            '';
          };
        };
      });
    };

    shares = mkOption {
      description = "Shared directory trees";
      default = [];
      type = with types; listOf (submodule ({ config, ... }: {
        options = {
          tag = mkOption {
            type = str;
            description = "Unique virtiofs daemon tag";
          };
          socket = mkOption {
            type = nullOr str;
            default =
              if config.proto == "virtiofs"
              then "${hostName}-virtiofs-${config.tag}.sock"
              else null;
            description = "Socket for communication with virtiofs daemon";
          };
          source = mkOption {
            type = nonEmptyStr;
            description = "Path to shared directory tree";
          };
          securityModel = mkOption {
            type = enum [ "passthrough" "none" "mapped" "mapped-file" ];
            default = "none";
            description = "What security model to use for the shared directory";
          };
          mountPoint = mkOption {
            type = path;
            description = "Where to mount the share inside the container";
          };
          proto = mkOption {
            type = enum [ "9p" "virtiofs" ];
            description = "Protocol for this share";
            default = "9p";
          };
        };
      }));
    };

    devices = mkOption {
      description = "PCI/USB devices that are passed from the host to the MicroVM";
      default = [];
      example = literalExpression /* nix */ ''
        [ {
          bus = "pci";
          path = "0000:01:00.0";
        } {
          bus = "pci";
          path = "0000:01:01.0";
          deviceExtraArgs = "id=hostId,x-igd-opregion=on";
        } {
          # QEMU only
          bus = "usb";
          path = "vendorid=0xabcd,productid=0x0123";
        } ]
      '';
      type = with types; listOf (submodule {
        options = {
          bus = mkOption {
            type = enum [ "pci" "usb" ];
            description = ''
              Device is either on the `pci` or the `usb` bus
            '';
          };
          path = mkOption {
            type = str;
            description = ''
              Identification of the device on its bus
            '';
          };
          qemu.deviceExtraArgs = mkOption {
            type =  with types; nullOr str;
            default = null;
            description = ''
              Device additional arguments (optional)
            '';
          };
        };
      });
    };

    vsock.cid = mkOption {
      default = null;
      type = with types; nullOr int;
      description = ''
        Virtual Machine address;
        setting it enables AF_VSOCK

        The following are reserved:
        - 0: Hypervisor
        - 1: Loopback
        - 2: Host
      '';
    };

    kernelParams = mkOption {
      type = with types; listOf str;
      description = "Includes boot.kernelParams but doesn't end up in toplevel, thereby allowing references to toplevel";
    };

    storeOnDisk = mkOption {
      type = types.bool;
      default = ! lib.any ({ source, ... }:
        source == "/nix/store"
      ) config.microvm.shares;
      description = "Whether to boot with the storeDisk, that is, unless the host's /nix/store is a microvm.share.";
    };

    writableStoreOverlay = mkOption {
      type = with types; nullOr str;
      default = null;
      example = "/nix/.rw-store";
      description = ''
        Path to the writable /nix/store overlay.

        If set to a filesystem path, the initrd will mount /nix/store
        as an overlay filesystem consisting of the read-only part as a
        host share or from the built storeDisk, and this configuration
        option as the writable overlay part. This allows you to build
        nix derivations *inside* the VM.

        Make sure that the path points to a writable filesystem
        (tmpfs, volume, or share).
      '';
    };

    graphics.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable GUI support.

        MicroVMs with graphics are intended for the interactive
        use-case. They cannot be started through systemd jobs.

        Support in Hypervisors:
        - `qemu` starts a Gtk window with the framebuffer of the virtio-gpu
      '';
    };

    graphics.socket = mkOption {
      type = types.str;
      default = "${hostName}-gpu.sock";
      description = ''
        Path of vhost-user socket
      '';
    };

    qemu.machine = mkOption {
      type = types.str;
      description = ''
        QEMU machine model, eg. `microvm`, or `q35`

        Get a full list with `qemu-system-x86_64 -M help`

        This has a default declared with `lib.mkDefault` because it
        depends on ''${pkgs.system}.
      '';
    };

    qemu.machineOpts = mkOption {
      type = with types; nullOr (attrsOf str);
      default = null;
      description = "Overwrite the default machine model options.";
    };

    qemu.extraArgs = mkOption {
      type = with types; listOf str;
      default = [];
      description = "Extra arguments to pass to qemu.";
    };

    qemu.serialConsole = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable the virtual serial console on qemu.
      '';
    };

    cloud-hypervisor.extraArgs = mkOption {
      type = with types; listOf str;
      default = [];
      description = "Extra arguments to pass to cloud-hypervisor.";
    };

    crosvm.extraArgs = mkOption {
      type = with types; listOf str;
      default = [];
      description = "Extra arguments to pass to crosvm.";
    };

    crosvm.pivotRoot = mkOption {
      type = with types; nullOr str;
      default = null;
      description = "A Hypervisor's sandbox directory";
    };

    prettyProcnames = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Set a recognizable process name right before executing the Hyperisor.
      '';
    };

    virtiofsd.inodeFileHandles = mkOption {
      type = with types; nullOr (enum [
        "never" "prefer" "mandatory"
      ]);
      default = null;
      description = ''
        When to use file handles to reference inodes instead of O_PATH file descriptors
        (never, prefer, mandatory)

        Allows you to overwrite default behavior in case you hit "too
        many open files" on eg. ZFS.
        <https://gitlab.com/virtio-fs/virtiofsd/-/issues/121>
      '';
    };

    virtiofsd.threadPoolSize = mkOption {
      type = with types; oneOf [ str ints.unsigned ];
      default = "`nproc`";
      description = ''
        The amounts of threads virtiofsd should spawn. This option also takes the special
        string `\`nproc\`` which spawns as many threads as the host has cores.
      '';
    };

    virtiofsd.extraArgs = mkOption {
      type = with types; listOf str;
      default = [];
      description = ''
        Extra command-line switch to pass to virtiofsd.
      '';
    };

    runner = mkOption {
      description = "Generated Hypervisor runner for this NixOS";
      type = with types; attrsOf package;
    };

    declaredRunner = mkOption {
      description = "Generated Hypervisor declared by `config.microvm.hypervisor`";
      type = types.package;
      default = config.microvm.runner.${config.microvm.hypervisor};
      defaultText = literalExpression ''"config.microvm.runner.''${config.microvm.hypervisor}"'';
    };

    binScripts = mkOption {
      description = ''
        Script snippets that end up in the runner package's bin/ directory
      '';
      default = {};
      type = with types; attrsOf lines;
    };

    storeDiskType = mkOption {
      type = types.enum [ "squashfs" "erofs" ];
      description = ''
        Boot disk file system type: squashfs is smaller, erofs is supposed to be faster.

        Defaults to erofs, unless the NixOS hardened profile is detected.
      '';
    };

    storeDiskErofsFlags = mkOption {
      type = with types; listOf str;
      description = ''
        Flags to pass to mkfs.erofs

        Omit `"-Efragments"` and `"-Ededupe"` to enable multi-threading.
      '';
      default =
        [ "-zlz4hc" ]
        ++
        lib.optional (kernelAtLeast "5.16") "-Eztailpacking"
        ++
        lib.optionals (kernelAtLeast "6.1") [
          # not implemented with multi-threading
          "-Efragments"
          "-Ededupe"
        ];
      defaultText = lib.literalExpression ''
        [ "-zlz4hc" ]
          ++ lib.optional (kernelAtLeast "5.16") "-Eztailpacking"
          ++ lib.optionals (kernelAtLeast "6.1") [
          "-Efragments"
          "-Ededupe"
        ]
        '';
    };

    storeDiskSquashfsFlags = mkOption {
      type = with types; listOf str;
      description = "Flags to pass to gensquashfs";
      default = [ "-c" "zstd" "-j" "$NIX_BUILD_CORES" ];
    };

    systemSymlink = mkOption {
      type = types.bool;
      default = !config.microvm.storeOnDisk;
      description = ''
        Whether to inclcude a symlink of `config.system.build.toplevel` to `share/microvm/system`.
        This is required for commands like `microvm -l` to function but removes reference to the uncompressed store content when using a disk image for the nix store.
      '';
    };
  };

  config = lib.mkMerge [ {
    microvm.qemu.machine =
      lib.mkIf (pkgs.stdenv.system == "x86_64-linux") (
        lib.mkDefault "microvm"
      );
  } {
    microvm.qemu.machine =
      lib.mkIf (pkgs.stdenv.system == "aarch64-linux") (
        lib.mkDefault "virt"
      );
  } ];
}
