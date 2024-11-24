# Frequently Asked Questions

## Are there elaborate example setups?

microvm.nix is used in these open-source infrastructure projects:

- [C3D2 services](https://gitea.c3d2.de/c3d2/nix-config)
- [DD-IX services](https://github.com/dd-ix/nix-config)

Let us know if you know more!

## Can I support the development and maintenance of this project?

[❤ Sponsor](https://github.com/sponsors/astro)

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
    "L+ /var/log/journal/${machineId} - - - - /var/lib/microvms/${vmHost}/journal/${machineId}"
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
  pkgs.writeShellScriptBin "update-microvm" ''
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

## Can I include my host's `<nixpkgs>` channel when building the VM?

Use the following configuration if you build your MicroVM with
`--impure` from channels, not Flakes:

```nix
nix.nixPath = [
  "nixpkgs=${builtins.storePath <nixpkgs>}"
];
```

## How do I let the `microvm` user access block devices?

You can re-add the following line to your host's NixOS configuration
which was removed from microvm.nix:

```nix
users.users.microvm.extraGroups = [ "disk" ];
```

The more secure solution would be writing custom
`services.udev.extraRules` that assign ownership/permissions to the
individually used block devices.

## My virtiofs-shared sops-nix /run/secrets disappears when the host is updated!

A workaround may be setting `sops.keepGenerations = 0;`, effectively
stopping sops-nix from ever removing old generations in
`/run/secrets.d/`.

That means that you still must reboot all MicroVMs to adapt any
updated secrets.
