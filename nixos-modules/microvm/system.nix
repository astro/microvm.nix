{ pkgs, lib, config, ... }:

{
  config = lib.mkIf config.microvm.guest.enable {
    assertions = [
      {assertion = (config.microvm.writableStoreOverlay != null) -> (!config.nix.optimise.automatic && !config.nix.settings.auto-optimise-store);
       message = ''
         `nix.optimise.automatic` and `nix.settings.auto-optimise-store` do not work with `microvm.writableStoreOverlay`.
       '';}];


    boot.loader.grub.enable = false;
    # boot.initrd.systemd.enable = lib.mkDefault true;
    boot.initrd.kernelModules = [
      "virtio_mmio"
      "virtio_pci"
      "virtio_blk"
      "9pnet_virtio"
      "9p"
      "virtiofs"
    ] ++ lib.optionals (
      pkgs.stdenv.targetPlatform.system == "x86_64-linux" &&
      config.microvm.hypervisor == "firecracker"
    ) [
      # Keyboard controller that can receive CtrlAltDel
      "i8042"
    ] ++ lib.optionals (config.microvm.writableStoreOverlay != null) [
      "overlay"
    ];

    microvm.kernelParams = config.boot.kernelParams ++ [
      "init=${config.system.build.toplevel}/init"
    ];

    # modules that consume boot time but have rare use-cases
    boot.blacklistedKernelModules = [
      "rfkill" "intel_pstate"
    ] ++ lib.optional (!config.microvm.graphics.enable) "drm";

    systemd =
      let
        # nix-daemon works only with a writable /nix/store
        enableNixDaemon = config.microvm.writableStoreOverlay != null;
      in {
        services.nix-daemon.enable = lib.mkDefault enableNixDaemon;
        sockets.nix-daemon.enable = lib.mkDefault enableNixDaemon;

        # consumes a lot of boot time
        services.mount-pstore.enable = false;

        # just fails in the usual usage of microvm.nix
        generators = { systemd-gpt-auto-generator = "/dev/null"; };
      };

  };
}
