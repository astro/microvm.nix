# Imperative MicroVM management with the `microvm` command

Compartmentizing services in an infrastructure landscape allows us to
conduct maintainance individually and without affecting unrelated
MicroVMs. The `microvm` command helps with that.

## Create a MicroVM

You can specify this MicroVM's source flake with `-f`. If omitted, the
tool will assume `git+file:///etc/nixos`. The source flakeref will be
kept in `/var/lib/microvm/*/flake` for future updating the MicroVM.

```bash
microvm -f git+https://... -c my-microvm
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

Listing your MicroVMs is a basically as easy as `ls /var/lib/microvm`

For more insight, the following command will read the current system
version of all MicroVMs and compare them to what the corresponding
flake evaluates. It is therefore quite slow to run, yet useful.

```bash
microvm -l
```
