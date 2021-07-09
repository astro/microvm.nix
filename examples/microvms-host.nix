{ self, nixpkgs, system }:

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    self.nixosModules.host

    ({ pkgs, lib, options, ... }: {
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
      virtualisation = lib.optionalAttrs (options.virtualisation ? qemu) {
        # larger than the defaults
        memorySize = 8192;
        cores = 12;
        diskSize = 8192;
        # 9P performance optimization that quelches a qemu warning
        msize = 65536;
        # allow building packages
        writableStore = true;
        # # keep the store paths built inside the VM across reboots
        # writableStoreUseTmpfs = false;

        qemu.options = [
          # faster virtio-console
          "-serial null"
          "-device virtio-serial"
          "-chardev stdio,mux=on,id=char0,signal=off"
          "-mon chardev=char0,mode=readline"
          "-device virtconsole,chardev=char0,nr=0"
        ];

        # use virtio's hvc0 as system console
        qemu.consoles = ["tty0" "hvc0"];

        # headless qemu
        graphics = false;
      };

      microvm.vms.qemu-example-with-tap = {
        flake = self;
        updateFlake = "microvm";
      };
      microvm.vms.firecracker-example-with-tap = {
        flake = self;
        updateFlake = "microvm";
      };
      microvm.vms.cloud-hypervisor-example-with-tap = {
        flake = self;
        updateFlake = "microvm";
      };
      microvm.vms.crosvm-example = {
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
          # Hand IP addresses to MicroVMs
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
          matchConfig.Name = "*-eth0";
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
