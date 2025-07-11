{ self, nixpkgs, system }:

let
  variants = [
    # hypervisor
    [ {
      id = "qemu";
      modules = [ {
        microvm.hypervisor = "qemu";
      } ];
    } {
      id = "qemu-tcg";
      modules = let
        # Emulate a different guest system than the host one
        guestSystem = if "${system}" == "x86_64-linux" then "aarch64-unknown-linux-gnu"
          else "x86_64-linux";
      in [
        {
          microvm = {
            hypervisor = "qemu";
            # Force the CPU to be something else than the current
            # system, and thus, emulated with qemu's Tiny Code Generator
            # (TCG)
            cpu = if "${system}" == "x86_64-linux" then "cortex-a53"
              else "Westmere";
          };
          nixpkgs.crossSystem.config = guestSystem;
        }
      ];
    } {
      id = "cloud-hypervisor";
      modules = [ {
        microvm.hypervisor = "cloud-hypervisor";
      } ];
    } {
      id = "crosvm";
      modules = [ {
        microvm.hypervisor = "crosvm";
      } ];
    } {
      id = "firecracker";
      modules = [ {
        microvm.hypervisor = "firecracker";
      } ];
    } {
      id = "kvmtool";
      modules = [ {
        microvm.hypervisor = "kvmtool";
      } ];
    } {
      id = "alioth";
      modules = [ {
        microvm.hypervisor = "alioth";
      } ];
    } ]
    # ro-store
    [ {
      # squashfs/erofs
      id = null;
    } {
      # 9pfs
      id = "9pstore";
      modules = [ ({ config, ... }: {
        microvm = {
          shares = [ {
            proto = "9p";
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
          } ];
          testing.enableTest = builtins.elem config.microvm.hypervisor [
            # Hypervisors that support 9p
            "qemu" "crosvm" "kvmtool"
          ];
        };
      }) ];
    } ]
    # rw-store
    [ {
      # none
      id = null;
    } {
      # overlay volume
      id = "overlay";
      modules = [ ({ config, ... }: {
        microvm.writableStoreOverlay = "/nix/.rw-store";
        microvm.volumes = [ {
          image = "nix-store-overlay.img";
          label = "nix-store";
          mountPoint = config.microvm.writableStoreOverlay;
          size = 128;
        } ];
      }) ];
    } ]
    # boot.systemd
    [ {
      # no
      id = null;
      modules = [ {
        boot.initrd.systemd.enable = false;
      } ];
    } {
      id = "systemd";
      modules = [ {
        boot.initrd.systemd.enable = true;
      } ];
    } ]
    # hardened profile
    [ {
      # no
      id = null;
    } {
      id = "hardened";
      modules = [ ({ modulesPath, ... }: {
        imports = [ "${modulesPath}/profiles/hardened.nix" ];
      }) ];
    } ]

    [ {
      # no
      id = null;
    } {
      id = "credentials";
      modules = [ ({ config, pkgs, ... }: {
        # This is the guest vm config
        microvm.credentialFiles.SECRET_BOOTSRAP_KEY = "/etc/microvm-bootstrap.secret";
        microvm.testing.enableTest = builtins.elem config.microvm.hypervisor [
          # Hypervisors that support systemd credentials
          "qemu"
        ];
        # TODO: need to somehow have the test harness check for the success or failure of this service.
        systemd.services.test-secret-availability = {
          serviceConfig = {
            ImportCredential = "SECRET_BOOTSRAP_KEY";
            Restart = "no";
          };
          path = [ pkgs.gnugrep pkgs.coreutils ];
          script = ''
            cat $CREDENTIALS_DIRECTORY/SECRET_BOOTSRAP_KEY | grep -q "i am super secret"
            if [ $? -ne 0 ]; then
              echo "Secret not found at $CREDENTIALS_DIRECTORY/SECRET_BOOTSRAP_KEY"
              exit 1
            fi
          '';
        };
      }) ];
    } ]

  ];

  allVariants =
    let
      go = variants:
        if variants == []
        then []
        else builtins.concatMap (head:
          let
            tail = go (builtins.tail variants);
          in
            if tail == []
            then [ [ head ] ]
            else map (t: [ head ] ++ t) tail
        ) (builtins.head variants);
    in
      go variants;

  makeTestConfigs = { modules, system, name }:
    builtins.foldl' (result: variant:
      let
        configName = builtins.concatStringsSep "-" (
          builtins.filter (s: s != null) (
            map ({ id ? null, ... }: id) variant
            ++
            [ name ]
          ));
        nixOS = nixpkgs.lib.nixosSystem {
          inherit system;
          modules =
            [ self.nixosModules.microvm
              ({ lib, ... }: {
              options.microvm.testing.enableTest = lib.mkOption {
                type = lib.mkOptionType {
                  name = "bool merged all true";
                  merge = loc: defs:
                    builtins.all (def: def.value) defs;
                };
                default = true;
              };
            }) ]
            ++
            modules
            ++
            builtins.concatMap ({ modules ? [], ... }: modules) variant;
        };
      in
        result
        //
        nixpkgs.lib.optionalAttrs nixOS.config.microvm.testing.enableTest {
          ${configName} = nixOS;
        }
    ) {} allVariants;

    args = {
      inherit self nixpkgs system;
      inherit makeTestConfigs;
    };

in
import ./shellcheck.nix args //

import ./startup-shutdown.nix args //
import ./shutdown-command.nix args //

builtins.foldl' (result: hypervisor:
  let
    args = {
      inherit self nixpkgs system hypervisor;
    };
  in
    result //
    import ./vm.nix args //
    import ./iperf.nix args
) {} self.lib.hypervisors
