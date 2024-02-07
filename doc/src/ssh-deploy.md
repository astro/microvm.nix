# Deploying via SSH

By running either from packages or through systemd services
microvm.nix tries to support a wholesome Nix workflow: develop and
test on your local laptop, then deploy to staging and later to
production.

Let's explore alternative ways before detailing our elaboration:

- You could build
  `.#nixosConfiguration.my-microvm.config.microvm.declaredRunner`
  locally, then `nix copy` it to the target host for
  installation. This comes at the expense of your laptop's battery
  time and it can also become quite network-heavy.
- You may transfer each change to the remote host to build entirely
  remote. There you're going to have a repository state that is going
  to confuse fellow operators. Also, your local `--override-input`
  parameters will become meaningless on the remote filesystem.

## microvm.deploy.rebuild

The *easy* interface that is named after `nixos-rebuild` combines the
two scripts that are described below:

- First, we evaluate locally and build remotely with
  `microvm.deploy.installOnHost`
- Depending on whether the host's `/nix/store` is mounted and SSH is
  running in the MicroVM:
  - We either run `microvm.deploy.sshSwitch` as described below
  - Alternatively, we restart the MicroVM's systemd service on the
    host

Because it needs to know about both the host and the MicroVM, these
ssh addresses must come before the actual `switch` argument:

```
nix run .#nixosConfigurations.my-microvm.config.microvm.deploy.rebuild root@example.com root@my-microvm.example.com switch
```

## microvm.deploy.installOnHost

This script will evaluate only the system's derivations locally. It
then transfers these and their dependencies to the remote system so
the actual build can be performed there.

Just like [the microvm command](microvm-command.md), it then installs
the MicroVM under `/var/lib/microvms/$NAME` so that the systemd
services of the `host` module can pick it up.

It is irrelevant whether you create a new MicrVOM or update an
existing one.

## microvm.deploy.sshSwitch

Once the host has an updated MicroVM in its `/nix/store` (see above)
the new system must be activated. For a proper state, this script does
a bit more in the MicroVM than just `switch-to-configuration`:

- First, the `config.networking.hostName` is compared to the running
  system for safety reasons.
- The Nix database registration will be imported which is important if
  you build packages into a `microvm.writableStoreOverlay`.
- The new system is installed into `/nix/var/nix/profiles/system`
  which is optional but expected by some Nix tooling.
- Finally, run `switch-to-configuration` with the provided parameter
  (eg. `switch`).
