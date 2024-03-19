{ nixpkgs-lib }:
rec {
  hypervisors = [
    "qemu"
    "cloud-hypervisor"
    "firecracker"
    "crosvm"
    "kvmtool"
    "stratovirt"
  ];

  hypervisorsWithNetwork = hypervisors;

  defaultFsType = "ext4";

  withDriveLetters = { volumes, hypervisor, storeOnDisk, ... }:
    let
      offset =
        if storeOnDisk
        then 1
        else 0;
    in
    map
      ({ fst, snd }:
        fst // {
          letter = snd;
        }
      )
      (nixpkgs-lib.zipLists volumes (
        nixpkgs-lib.drop offset nixpkgs-lib.strings.lowerChars
      ));

  createVolumesScript = pkgs: pkgs.lib.concatMapStringsSep "\n" (
    { image
    , label
    , size ? throw "Specify a size for volume ${image} or use autoCreate = false"
    , fsType ? defaultFsType
    , autoCreate ? true
    , ...
    }: pkgs.lib.warnIf
      (label != null && !autoCreate) "Volume is not automatically labeled unless autoCreate is true. Volume has to be labeled manually, otherwise it will not be identified"
      (
        let
          labelOption =
            if autoCreate then
              (if builtins.elem fsType [ "ext2" "ext3" "ext4" "xfs" ] then "-L"
              else if fsType == "vfat" then "-n"
              else
                (pkgs.lib.warnIf (label != null)
                  "Will not label volume ${label} with filesystem type ${fsType}. Open an issue on the microvm.nix project to request a fix."
                  null))
            else null;
          labelArgument =
            if (labelOption != null && label != null) then "${labelOption} '${label}'"
            else "";
        in
        (nixpkgs-lib.optionalString autoCreate ''
          PATH=$PATH:${with pkgs.buildPackages; lib.makeBinPath [ coreutils util-linux e2fsprogs xfsprogs dosfstools ]}

          if [ ! -e '${image}' ]; then
            touch '${image}'
            # Mark NOCOW
            chattr +C '${image}' || true
            fallocate -l${toString size}MiB '${image}'
            mkfs.${fsType} ${labelArgument} '${image}'
          fi
        '')
      )
  );

  buildRunner = import ./runner.nix;

  makeMacvtap = { microvmConfig, hypervisorConfig }:
    import ./macvtap.nix {
      inherit microvmConfig hypervisorConfig;
      lib = nixpkgs-lib;
    };
}
