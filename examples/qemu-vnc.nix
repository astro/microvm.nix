{ self
, nixpkgs
, system
, packages ? ""
, tapInterface ? null
}:

# Before running: $ mkdir /tmp/share
# Run with: $ nix run microvm#qemu-vnc
# Connect with: $ nix shell nixpkgs#tigervnc -c vncviewer localhost:5900

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    # this runs as a MicroVM
    self.nixosModules.microvm

    ({ config, lib, pkgs, ... }: {
      microvm = {
        hypervisor = "qemu";
        interfaces = lib.optional (tapInterface != null) {
          type = "tap";
          id = tapInterface;
          mac = "00:00:00:00:00:02";
        };
      };

      networking.hostName = "qemu-vnc";
      system.stateVersion = config.system.nixos.version;

      microvm.qemu.extraArgs = [
        "-vnc" ":0"
        "-vga" "qxl"
        # needed for mounse/keyboard input via vnc
        "-device" "virtio-keyboard"
        "-usb"
        "-device" "usb-tablet,bus=usb-bus.0"
      ];

      services.getty.autologinUser = "user";
      users.users.user = {
        password = "";
        group = "user";
        isNormalUser = true;
        extraGroups = [ "wheel" "video" ];
      };
      users.groups.user = { };
      security.sudo = {
        enable = true;
        wheelNeedsPassword = false;
      };

      services.xserver = {
        enable = true;
        desktopManager.xfce.enable = true;
        displayManager.autoLogin.user = "user";
      };

      hardware.opengl.enable = true;

      environment.systemPackages = with pkgs; [
        xdg-utils # Required
      ] ++ map
        (package:
          lib.attrByPath (lib.splitString "." package) (throw "Package ${package} not found in nixpkgs") pkgs
        )
        (
          builtins.filter
            (package:
              package != ""
            )
            (lib.splitString " " packages));

    })
  ];
}
