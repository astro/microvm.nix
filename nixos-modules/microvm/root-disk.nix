{ config, lib, pkgs, ... }:

let
  self-lib = import ../../lib {
    nixpkgs-lib = lib;
  };

  regInfo = pkgs.closureInfo {
    rootPaths = [ config.system.build.toplevel ];
  };

  inherit (config.system.boot.loader) kernelFile initrdFile;

  kernelPath =
    "${config.boot.kernelPackages.kernel}/${kernelFile}";
  initrdPath =
    "${config.system.build.initialRamdisk}/${initrdFile}";

in {
  options.microvm = with lib; {
    bootDiskType = mkOption {
      type = types.enum [ "squashfs" "erofs" ];
      default = "squashfs";
      description = ''
        Boot disk file system type: squashfs is smaller, erofs is supposed to be faster.
      '';
    };

    bootDisk = mkOption {
      type = types.path;
      # default = {
      #   inherit (config.system.build) squashfs erofs;
      # }.${config.microvm.bootDiskType};
      # defaultText = literalExpression ''"''${config.system.build.squashfs}"'';
    };
  };

  config = lib.mkIf config.microvm.guest.enable {
    boot.initrd.availableKernelModules = [
      config.microvm.bootDiskType
    ];

    microvm.bootDisk = pkgs.runCommandLocal "microvm-bootdisk.img" {
      nativeBuildInputs = with pkgs; [
        parted
        libguestfs
      ] ++ {
        squashfs = [ squashfsTools ];
        erofs = [ erofs-utils ];
      }.${config.microvm.bootDiskType};
      LIBGUESTFS_PATH = pkgs.libguestfs-appliance;
      passthru = {
        inherit regInfo;
        kernel = kernelPath;
        initrd = initrdPath;
      };
    } ''
      # kernel + initrd + slack, in sectors
      EFI_SIZE=$(( ( ( $(stat -c %s ${kernelPath}) + $(stat -c %s ${initrdPath}) + 16 * 4096 ) / ( 2048 * 512 ) + 1 ) * 2048 ))

      ${lib.optionalString config.microvm.storeOnBootDisk ''
        echo Copying a /nix/store
        mkdir store
        for d in $(sort -u ${
          lib.concatMapStringsSep " " pkgs.writeReferencesToFile (
            pkgs.lib.optionals config.microvm.storeOnBootDisk [
              config.system.build.toplevel
              regInfo
            ]
          )
        }); do
          cp -a $d store
        done

        echo Creating a ${config.microvm.bootDiskType}
        ${{
          "squashfs" = ''
            mksquashfs store store.part \
              -reproducible -all-root -4k-align
          '';
          "erofs" = ''
            mkfs.erofs -zlz4hc store.part store
          '';
        }.${config.microvm.bootDiskType}}

        echo Cleaning up store
        chmod -R u+w store
        rm -rf store

        echo Copying store ${config.microvm.bootDiskType} into disk
        dd if=store.part of=$out bs=512 seek=$(( $EFI_SIZE + 2048 ))
        # In bytes
        STORE_SIZE=$(stat -c %s store.part)
        # In sectors
        TOTAL_SIZE=$(( $EFI_SIZE + 2048 + $STORE_SIZE / 512 + 33 ))
        rm store.part
        dd if=/dev/zero of=$out bs=512 seek=$(( $TOTAL_SIZE - 1 )) count=1
      ''}
      ${lib.optionalString (!config.microvm.storeOnBootDisk) ''
        truncate -s $(( ( $EFI_SIZE + 2048 + 33 ) * 512 )) $out
      ''}
      echo Creating partition table
      parted --script $out -- \
        mklabel gpt \
        mkpart ESP fat32 2048s $(( $EFI_SIZE + 2048 - 1 ))"s" \
        set 1 boot on
      ${lib.optionalString config.microvm.storeOnBootDisk ''
        parted --script $out -- \
          mkpart store $(( $EFI_SIZE + 2048 ))"s" $(( $EFI_SIZE + 2048 + ( $STORE_SIZE + 511 ) / 512 - 1))"s"
      ''}

      echo Creating EFI partition
      export HOME=`pwd`
      guestfish --add $out run \: mkfs fat /dev/sda1
      guestfs() {
        guestfish --add $out --mount /dev/sda1:/ $@
      }
      guestfs mkdir /loader
      echo 'default *.conf' > loader.conf
      guestfs copy-in loader.conf /loader/
      guestfs mkdir /loader/entries
      cat > entry.conf <<EOF
      title microvm.nix (${config.system.nixos.label})
      linux /${kernelFile}
      initrd /${initrdFile}
      options ${lib.concatStringsSep " " config.microvm.kernelParams} verbose console=hvc0 console=ttyS0 reboot=t panic=-1
      EOF
      guestfs copy-in entry.conf /loader/entries/
      guestfs copy-in ${kernelPath} /
      guestfs copy-in ${initrdPath} /
    '';

    microvm.kernelParams = [
      "regInfo=${regInfo}/registration"
    ];
    boot.postBootCommands = lib.mkIf config.nix.enable ''
      if [[ "$(cat /proc/cmdline)" =~ regInfo=([^ ]*) ]]; then
        ${config.nix.package.out}/bin/nix-store --load-db < ''${BASH_REMATCH[1]}
      fi
    '';
  };
}
