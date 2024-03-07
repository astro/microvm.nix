{ self
, nixpkgs
, nixbsd
, system
, ...
}:

nixbsd.lib.nixbsdSystem {
  inherit (nixpkgs) lib;
  nixpkgsPath = nixpkgs.outPath;
  #specialArgs = { nixFlake = nix; } // (args.specialArgs or { });
  modules = [
    # this runs as a MicroVM
    self.nixosModules.nixbsd-microvm

    ({ config, lib, pkgs, ... }: {
      nixpkgs.buildPlatform = system;
      nixpkgs.hostPlatform = "x86_64-freebsd";
      nixpkgs.config.freebsdBranch = "releng/14.0";

      users.users.root.initialPassword = "toor";

      # Don't make me wait for an address...
      networking.dhcpcd.wait = "background";

      networking.hostName = "nixbsd-base";
      microvm = {
        hypervisor = "cloud-hypervisor";
        vcpu = 2;
        # graphics.enable = true;
        # interfaces = lib.optional (tapInterface != null) {
        #   type = "tap";
        #   id = tapInterface;
        #   mac = "00:00:00:00:00:02";
        # };
      };

      # networking.hostName = "qemu-vnc";
      # system.stateVersion = config.system.nixos.version;
    })
  ];
}
