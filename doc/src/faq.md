# Frequently Asked Questions

## Can I support the development and maintenance of this project?

[❤ Sponsor](https://github.com/sponsors/astro)

## How can I make my MicroVM smaller?

For the system NixOS already offers a few knobs to shrink an
installation for non-graphical usage:

```nix
{
  environment.noXlibs = true;
  documentation.enable = false;
  documentation.nixos.enable = false;
}
```

Some hypervisors have more dependencies than others, yet QEMU remains
unmatched. You can try to use the more minimal QEMU package that is
actually intended for NixOS tests:

```nix
nixpkgs.config.packageOverrides = pkgs: {
  qemu_kvm = pkgs.qemu_test;
};
```

## How to centralize logging with journald?

That is possible without even requiring a network transport by just
making the journals available to the host as a share. Because journald
identifies hosts by their `/etc/machine-id`, we propose to use static
content for that file. Add a NixOS module like the following to your
MicroVM configuration:

```nix
environment.etc."machine-id" = {
  mode = "0644";
  text =
    # change this to suit your flake's interface
    self.lib.addresses.machineId.${config.networking.hostName} + "\n";
};

microvm.shares = [ {
  # On the host
  source = "/var/lib/microvms/${config.networking.hostName}/journal";
  # In the MicroVM
  mountPoint = "/var/log/journal";
  tag = "journal";
  proto = "virtiofs";
  socket = "journal.sock";
} ];
```

Last, make the MicroVM journals available to your host. The
`machine-id` must be available.

```nix
systemd.tmpfiles.rules = map (vmHost:
  let
    machineId = self.lib.addresses.machineId.${vmHost};
  in
    # creates a symlink of each MicroVM's journal under the host's /var/log/journal
    "L+ /var/log/journal/${machineId} - - - /var/lib/microvms/${vmHost}/journal/${machineId}"
) (builtins.attrNames self.lib.addresses.machineId);
```

Once your MicroVM's journal data is visible in the
`/var/log/journal/$machineId/` directories, `journalctl` can pick it
up using the `-m`/`--merge` switch.

## Can I build with hypervisors from the host's nixpkgs instead of the MicroVM's?

Yes. This scenario is enabled through the flake's `lib.buildRunner`
function. See the [`nix run
microvm#build-microvm`](https://github.com/astro/microvm.nix/blob/main/pkgs/build-microvm.nix)
script that you will need to customize to fit your deployment scenario.

## How can I deploy imperatively from Continuous Integration?

Do this by integrating into your automation what the `microvm` command
does.

```nix
environment.systemPackages = [ (
  # Provide a manual updating script that fetches the latest
  # updated+built system from Hydra
  pkgs.writeScriptBin "update-microvm" ''
    #! ${pkgs.runtimeShell} -e

    if [ $# -lt 1 ]; then
      NAMES="$(ls -1 /var/lib/microvms)"
    else
      NAMES="$@"
    fi

    for NAME in $NAMES; do
      echo MicroVM $NAME
      cd /var/lib/microvms/$NAME
      # Is this truly the flake that is being built on Hydra?
      if [ "$(cat flake)" = "git+https://gitea.example.org/org/nix-config?ref=flake-update" ]; then
        NEW=$(curl -sLH "Accept: application/json" https://hydra.example.org/job/org/nix-config/$NAME/latest | ${pkgs.jq}/bin/jq -er .buildoutputs.out.path)
        nix copy --from https://nix-cache.example.org $NEW

        if [ -e booted ]; then
          nix store diff-closures $(readlink booted) $NEW
        elif [ -e current ]; then
          echo "NOT BOOTED! Diffing to old current:"
          nix store diff-closures $(readlink current) $NEW
        else
          echo "NOT BOOTED?"
        fi

        CHANGED=no
        if ! [ -e current ]; then
          ln -s $NEW current
          CHANGED=yes
        elif [ "$(readlink current)" != $NEW ]; then
          rm -f old
          cp --no-dereference current old
          rm -f current
          ln -s $NEW current
          CHANGED=yes
        fi
      fi

      if [ "$CHANGED" = "yes" ]; then
        systemctl restart microvm@$NAME
      fi
      echo
    done
  ''
) ];
```
