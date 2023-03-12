# Frequently Asked Questions

A few caveats. Contributions to eliminate those are welcome.

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
