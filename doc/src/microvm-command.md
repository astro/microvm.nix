# Imperative MicroVM management with the `microvm` command

Compartmentalizing services in an infrastructure landscape allows us to
conduct maintenance individually and without affecting unrelated
MicroVMs. The `microvm` command helps with that.

## Create a MicroVM

You can specify this MicroVM's source flake with `-f`. If omitted, the
tool will assume `git+file:///etc/nixos`. The source flakeref will be
kept in `/var/lib/microvms/*/flake` for future updating the MicroVM.

```bash
microvm -f git+https://... -c my-microvm
```

### Enabling MicroVM autostart

Extension of the host's systemd units must happen declaratively in the
host's NixOS configuration:

```nix
microvm.autostart = [
  "myvm1"
  "myvm2"
  "myvm3"
];
```

## Update a MicroVM

*Updating* does not refresh your packages but simply rebuilds the
MicroVM. Use `nix flake update` to get new package versions.

```bash
microvm -u my-microvm
```

Until ways have been found to safely transfer the profile into the
target /nix/store, and subsequently activate it, you must restart the
MicroVM for the update to take effect.

Use the `-R` flag to automatically restart if an update was built.

## List MicroVMs

Listing your MicroVMs is as trivial as `ls -1 /var/lib/microvms`

For more insight, the following command will read the current system
version of all MicroVMs and compare them to what the corresponding
flake evaluates. It is therefore quite slow to run, yet useful.

```bash
microvm -l
```

## Removing MicroVMs

First, stop the MicroVM:

```bash
systemctl stop microvm@$NAME
```

If you don't use absolute filesystem paths for sockets, volumes, or
shares, all MicroVM state is kept under `/var/lib/microvms/$NAME/`.
The `microvm@.serivce` systemd service template depends on existence
of this directory.

```bash
rm -rf /var/lib/microvms/$NAME
```
