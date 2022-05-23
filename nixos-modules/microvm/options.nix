{ config, lib, ... }:
let
  self-lib = import ../../lib {
    nixpkgs-lib = lib;
  };
in
{
  options.microvm = with lib; {
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
      default = "${config.networking.hostName}.sock";
      type = with types; nullOr str;
    };

    user = mkOption {
      description = "User to switch to when started as root";
      default = null;
      type = with types; nullOr str;
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
      example = lib.literalExpression
        ''
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

          <warning><para>
            If the NixOS firewall on the virtual machine is enabled, you also
            have to open the guest ports to enable the traffic between host and
            guest.
          </para></warning>

          <note><para>Currently QEMU supports only IPv4 forwarding.</para></note>
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
          fsType = mkOption {
            type = str;
            default = "ext4";
            description = "File system for automatic creation and mounting";
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
            type = enum [ "user" "tap" "bridge" ];
          };
          id = mkOption {
            type = str;
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
          };
        };
      });
    };

    shares = mkOption {
      description = "Shared directory trees";
      default = [];
      type = with types; listOf (submodule {
        options = {
          tag = mkOption {
            type = str;
            description = "Unique virtiofs daemon tag";
          };
          socket = mkOption {
            type = nullOr str;
            default = null;
            description = "Socket for communication with virtiofs daemon";
          };
          source = mkOption {
            type = path;
            description = "Path to shared directory tree";
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
      });
    };

    kernelParams = mkOption {
      type = with types; listOf str;
      description = "Includes boot.kernelParams but doesn't end up in toplevel, thereby allowing references to toplevel";
    };

    storeOnBootDisk = mkOption {
      type = types.bool;
      default = ! lib.any ({ source, ... }:
        source == "/nix/store"
      ) config.microvm.shares;
      description = "Whether to include the required /nix/store on the boot disk.";
    };

    writableStoreOverlay = mkOption {
      type = with types; nullOr str;
      default = null;
      example = "/nix/.rw-store";
      description = ''
        Path to the writable /nix/store overlay.

        Make sure that the path points to a writable filesystem (tmpfs, volume, or share).
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
    };
  };

  config.assertions =
    # check for duplicate volume images
    map (volumes: {
      assertion = builtins.length volumes == 1;
      message = ''
        MicroVM ${config.networking.hostName}: volume image "${(builtins.head volumes).image}" is used ${toString (builtins.length volumes)} > 1 times.
      '';
    }) (
      builtins.attrValues (
        lib.groupBy ({ image, ... }: image) config.microvm.volumes
      )
    )
    ++
    # check for duplicate interface ids
    map (interfaces: {
      assertion = builtins.length interfaces == 1;
      message = ''
        MicroVM ${config.networking.hostName}: interface id "${(builtins.head interfaces).id}" is used ${toString (builtins.length interfaces)} > 1 times.
      '';
    }) (
      builtins.attrValues (
        lib.groupBy ({ id, ... }: id) config.microvm.interfaces
      )
    )
    ++
    # check for bridge interfaces
    map ({ id, type, bridge, ... }:
      if type == "bridge"
      then {
        assertion = bridge != null;
        message = ''
          MicroVM ${config.networking.hostName}: interface ${id} is of type "bridge"
          but doesn't have a bridge to attach to defined.
        '';
      }
      else {
        assertion = bridge == null;
        message = ''
          MicroVM ${config.networking.hostName}: interface ${id} is not of type "bridge"
          and therefore shouldn't have a "bridge" option defined.
        '';
      }
    ) config.microvm.interfaces
    ++
    # check for interface name length
    map ({ id, ... }: {
      assertion = builtins.stringLength id <= 15;
      message = ''
        MicroVM ${config.networking.hostName}: interface name ${id} is longer than the
        the maximum length of 15 characters on Linux.
      '';
    }) config.microvm.interfaces
    ++
    # check for duplicate share tags
    map (shares: {
      assertion = builtins.length shares == 1;
      message = ''
        MicroVM ${config.networking.hostName}: share tag "${(builtins.head shares).tag}" is used ${toString (builtins.length shares)} > 1 times.
      '';
    }) (
      builtins.attrValues (
        lib.groupBy ({ tag, ... }: tag) config.microvm.shares
      )
    )
    ++
    # check for duplicate share sockets
    map (shares: {
      assertion = builtins.length shares == 1;
      message = ''
        MicroVM ${config.networking.hostName}: share socket "${(builtins.head shares).socket}" is used ${toString (builtins.length shares)} > 1 times.
      '';
    }) (
      builtins.attrValues (
        lib.groupBy ({ socket, ... }: toString socket) (
          builtins.filter ({ proto, ... }: proto == "virtiofs")
            config.microvm.shares
        )
      )
    )
    ++
    # check for virtiofs shares without socket
    map ({ tag, socket, ... }: {
      assertion = socket != null;
      message = ''
        MicroVM ${config.networking.hostName}: virtiofs share with tag "${tag}" is missing a `socket` path.
      '';
    }) (
      builtins.filter ({ proto, ... }: proto == "virtiofs")
        config.microvm.shares
    )
    ++
    # blacklist forwardPorts
    [ {
      assertion = config.microvm.forwardPorts == [] || (
        config.microvm.hypervisor == "qemu" &&
        builtins.any ({ type, ... }: type == "user") config.microvm.interfaces
      );
      message = ''
        `config.microvm.forwardPorts` works only with qemu and one network interface with `type = "user"`
      '';
    } ]
  ;

  config.warnings =
    # 32 MB is just an optimistic guess, not based on experience
    lib.optional (config.microvm.mem < 32) ''
      MicroVM ${config.networking.hostName}: ${toString config.microvm.mem} MB of RAM is uncomfortably narrow.
    '';
}
