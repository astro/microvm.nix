{ config, pkgs }:

let
  inherit (config.system.build) extraUtils microvmStage1;
  regInfo = pkgs.closureInfo {
    rootPaths = [ config.system.build.toplevel ];
  };
in
pkgs.runCommandLocal "rootfs.squashfs" {
  buildInputs = [ pkgs.squashfsTools ];
  passthru.regInfo = regInfo;
} ''
  mkdir -p $(for d in nix/store mnt-root dev etc lib run proc sys tmp; do
    echo rootfs/$d
  done)
  ln -s ${extraUtils}/bin rootfs/bin
  ln -s ${microvmStage1} rootfs/init

  for d in $(sort -u ${
    pkgs.lib.concatMapStringsSep " " pkgs.writeReferencesToFile ([
      microvmStage1
      extraUtils
    ] ++
    pkgs.lib.optionals config.microvm.storeOnBootDisk [
      config.system.build.toplevel
      regInfo
    ]
  )}); do
    cp -a $d rootfs/nix/store
  done

  mksquashfs rootfs $out \
    -reproducible -all-root -4k-align
  du -hs $out
''
