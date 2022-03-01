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
      default = "/nix/.rw-store";
      description = "Path to the writable /nix/store overlay";
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
        lib.groupBy ({ socket, ... }: socket) (
          builtins.filter ({ proto, ... }: proto == "virtiofs")
            config.microvm.shares
        )
      )
    )
  ;

  config.warnings =
    # 32 MB is just an optimistic guess, not based on experience
    lib.optional (config.microvm.mem < 32) ''
      MicroVM ${config.networking.hostName}: ${toString config.microvm.mem} MB of RAM is uncomfortably narrow.
    '';
}
