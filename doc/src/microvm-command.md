# Imperative MicroVM management with the MicroVM command

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

```bash
microvm -u my-microvm
```

## List MicroVMs

Listing your MicroVMs is a basically as easy as `ls /var/lib/microvm`

For more insight, the following command will read the current system
version of all MicroVMs and compare them to what the corresponding
flake evaluates. It is therefore quite slow to run, yet useful.

```bash
microvm -l
```
