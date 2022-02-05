{ self, nixpkgs, system }:

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    # for declarative MicroVM management
    self.nixosModules.host
    # this runs as a MicroVM that nests MicroVMs
    self.nixosModules.microvm

    ({ pkgs, lib, ... }: {
      networking.hostName = "microvms-host";
      users.users.root.password = "";
      nix = {
        package = pkgs.nixFlakes;
        extraOptions = "experimental-features = nix-command flakes";
        registry = {
          nixpkgs.flake = nixpkgs;
          microvm.flake = self;
        };
      };
      environment.systemPackages = [
        pkgs.git
      ];
      services = let
        service = if lib.versionAtLeast (lib.versions.majorMinor lib.version) "20.09" then "getty" else "mingetty";
      in {
        ${service}.helpLine = ''
          Log in as "root" with an empty password.
          Type Ctrl-a c to switch to the qemu console
          and `quit` to stop the VM.
        '';
      };
      # Host MicroVM settings
      microvm = {
        mem = 8192;
        vcpu = 4;
      };

      # Nested MicroVMs
      microvm.vms."${system}-qemu-example-with-tap" = {
        flake = self;
        updateFlake = "microvm";
      };
      microvm.vms."${system}-firecracker-example-with-tap" = {
        flake = self;
        updateFlake = "microvm";
      };
      microvm.vms."${system}-cloud-hypervisor-example-with-tap" = {
        flake = self;
        updateFlake = "microvm";
      };
      microvm.vms."${system}-crosvm-example" = {
        flake = self;
        updateFlake = "microvm";
      };
      microvm.vms."${system}-kvmtool-example-with-tap" = {
        flake = self;
        updateFlake = "microvm";
      };

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
          addresses = [ {
            addressConfig.Address = "10.0.0.1/24";
          } {
            addressConfig.Address = "fd12:3456:789a::1/64";
          } ];
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
    })
  ];
}
