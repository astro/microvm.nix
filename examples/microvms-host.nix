# `nix run microvm#vm`
{ self, nixpkgs, system }:

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    # for declarative MicroVM management
    self.nixosModules.host
    # this runs as a MicroVM that nests MicroVMs
    self.nixosModules.microvm

    ({ config, lib, pkgs, ... }:
      let
        inherit (self.lib) hypervisors;

        hypervisorMacAddrs = builtins.listToAttrs (
          map (hypervisor:
            let
              hash = builtins.hashString "sha256" hypervisor;
              c = off: builtins.substring off 2 hash;
              mac = "${builtins.substring 0 1 hash}2:${c 2}:${c 4}:${c 6}:${c 8}:${c 10}";
            in {
              name = hypervisor;
              value = mac;
            }) hypervisors
        );

        hypervisorIPv4Addrs = builtins.listToAttrs (
          lib.imap0 (i: hypervisor: {
            name = hypervisor;
            value = "10.0.0.${toString (2 + i)}";
          }) hypervisors
        );

      in {
        networking.hostName = "microvms-host";
        system.stateVersion = config.system.nixos.version;
        users.users.root.password = "";
        users.motd = ''
          Once nested MicroVMs have booted you can look up DHCP leases:
          networkctl status virbr0

          They are configured to allow SSH login with root password:
          toor
        '';
        services.getty.autologinUser = "root";

        # Make alioth available
        nixpkgs.overlays = [ self.overlay ];

        # MicroVM settings
        microvm = {
          mem = 8192;
          vcpu = 4;
          # Use QEMU because nested virtualization and user networking
          # are required.
          hypervisor = "qemu";
          interfaces = [ {
            type = "user";
            id = "qemu";
            mac = "02:00:00:01:01:01";
          } ];
        };

        # Nested MicroVMs (a *host* option)
        microvm.vms = builtins.mapAttrs (hypervisor: mac: {
          config = {
            system.stateVersion = config.system.nixos.version;
            networking.hostName = "${hypervisor}-microvm";

            microvm = {
              inherit hypervisor;
              interfaces = [ {
                type = "tap";
                id = "vm-${builtins.substring 0 12 hypervisor}";
                inherit mac;
              } ];
            };
            # Just use 99-ethernet-default-dhcp.network
            systemd.network.enable = true;

            users.users.root.password = "toor";
            services.openssh = {
              enable = true;
              settings.PermitRootLogin = "yes";
            };
          };
        }) hypervisorMacAddrs;

        systemd.network = {
          enable = true;
          netdevs.virbr0.netdevConfig = {
            Kind = "bridge";
            Name = "virbr0";
          };
          networks.virbr0 = {
            matchConfig.Name = "virbr0";

            addresses = [ {
              addressConfig.Address = "10.0.0.1/24";
            } {
              addressConfig.Address = "fd12:3456:789a::1/64";
            } ];
            # Hand out IP addresses to MicroVMs.
            # Use `networkctl status virbr0` to see leases.
            networkConfig = {
              DHCPServer = true;
              IPv6SendRA = true;
            };
            # Let DHCP assign a statically known address to the VMs
            dhcpServerStaticLeases = lib.imap0 (i: hypervisor: {
              dhcpServerStaticLeaseConfig = {
                MACAddress = hypervisorMacAddrs.${hypervisor};
                Address = hypervisorIPv4Addrs.${hypervisor};
              };
            }) hypervisors;
            # IPv6 SLAAC
            ipv6Prefixes = [ {
              ipv6PrefixConfig.Prefix = "fd12:3456:789a::/64";
            } ];
          };
          networks.microvm-eth0 = {
            matchConfig.Name = "vm-*";
            networkConfig.Bridge = "virbr0";
          };
        };
        # Allow DHCP server
        networking.firewall.allowedUDPPorts = [ 67 ];
        # Allow Internet access
        networking.nat = {
          enable = true;
          enableIPv6 = true;
          internalInterfaces = [ "virbr0" ];
        };

        networking.extraHosts = lib.concatMapStrings (hypervisor: ''
          ${hypervisorIPv4Addrs.${hypervisor}} ${hypervisor}
        '') hypervisors;
      })
  ];
}
