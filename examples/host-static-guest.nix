# `nix run microvm#host-static-guests`
{ self, nixpkgs, system }:

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    # for declarative MicroVM management
    self.nixosModules.host
    # this runs as a MicroVM that nests another MicroVM
    # potentially the host doesn't have to be a MicroVM itself
    self.nixosModules.microvm

    ({ config, lib, pkgs, ... }:
      let
        host = {
          MAC = "02:00:00:00:00:01";
        };
        guest = {
          MAC = "02:00:00:00:00:02";
          ip4 = "10.0.0.123";
          service = {
            text = "Hello, World!";
            port = 1234;
          };
        };
      in
      {
        # === Basic Host Setup ===
        #
        # We just use a nested MicroVM to demonstrate the network configuration
        # on the host machine. This configuration can be used on a non-MicroVM
        # host as well without any further adaptations (besides taking care of
        # collisions with your personal network configuration)
        system.stateVersion = config.system.nixos.version;
        users.users.root.password = "";
        users.motd = ''
          Once the nested MicroVM has booted, you can reach the service hosted on it via:
          curl ${guest.ip4}:${builtins.toString guest.service.port}
        '';
        services.getty.autologinUser = "root";
        environment.systemPackages = [ pkgs.curl ];

        # MicroVM settings
        microvm = {
          mem = 1024 * 4;
          vcpu = 2;
          # Use QEMU because nested virtualization and user networking
          # are required.
          hypervisor = "qemu";
          interfaces = [{
            type = "user";
            id = "qemu";
            mac = host.MAC;
          }];
        };

        # === Basic Guest Setup ===
        # 
        # The guest machine is also just using a very minimalistic configuration.
        # It hosts a simple `static-web-server` showing a single website on a 
        # configurable port.

        # Nested MicroVM (a *host* option)
        microvm.vms.guest.config = {
          system.stateVersion = config.system.nixos.version;
          networking.hostName = "guest-microvm";

          microvm = {
            interfaces = [{
              type = "tap";
              id = "vm-guest";
              mac = guest.MAC;
            }];
          };

          # Just use 99-ethernet-default-dhcp.network
          systemd.network.enable = true;

          # = very basic service =

          networking.firewall.allowedTCPPorts = [ 80 443 guest.service.port ];
          services.static-web-server = {
            enable = true;
            listen = "[::]:${builtins.toString guest.service.port}";
            root = "${pkgs.writeTextDir "index.html" guest.service.text}";
          };

        };

        # === Network Setup ===
        #
        # The network config sets up a virtual bridge to connect to the guest 
        # machine. The bridge uses DHCP to dynamically hand out leases to the 
        # guest machines. Since we want to access the service on the guest machine
        # on a predicatable address, we can use a feature to map the MAC address  
        # of the guest machine to a static private ip

        systemd.network = {
          enable = true;
          netdevs.virbr0.netdevConfig = {
            Kind = "bridge";
            Name = "virbr0";
          };
          networks.virbr0 = {
            matchConfig.Name = "virbr0";
            # Hand out IP addresses to MicroVMs.
            # Use `networkctl status virbr0` to see leases.
            networkConfig = {
              DHCPServer = true;
              IPv6SendRA = true;
            };
            # here we can map the mac address of the guest system to static ip addresses
            dhcpServerStaticLeases = [
              {
                dhcpServerStaticLeaseConfig = {
                  MACAddress = guest.MAC;
                  Address = guest.ip4;
                };
              }
            ];
            addresses = [{
              addressConfig.Address = "10.0.0.1/24";
            }];
          };
          networks.microvm-eth0 = {
            matchConfig.Name = "vm-*";
            networkConfig.Bridge = "virbr0";
          };
        };

        networking = {
          hostName = "microvms-host";
          # Allow DHCP server
          firewall.allowedUDPPorts = [ 67 ];
          # # Allow Internet access
          nat = {
            enable = true;
            enableIPv6 = true;
            internalInterfaces = [ "virbr0" ];
          };
        };
      })
  ];
}
