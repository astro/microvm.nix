# Shares

In `microvm.shares` elements the `proto` field allows either of two
values:

- `9p` (default) is built into many hypervisors, allowing you to
  quickly share a directory tree

- `virtiofs` requires a separate virtiofsd service which is only
  started as a prerequisite when you start MicroVMs through a systemd
  service that comes with the `microvm.nixosModules.host` module.

  Expect `virtiofs` to yield better performance over `9p`.

## Sharing a host's `/nix/store`

If a share with `source = "/nix/store"` is defined, size and build
time of the stage1 squashfs for `/dev/vda` will be reduced
drastically.

```nix
microvm.shares = [ {
  tag = "ro-store";
  source = "/nix/store";
  mountPoint = "/nix/.ro-store";
} ];
```

## Writable `/nix/store` overlay

The writable layer is mounted from the path
`microvm.writableStoreOverlay`. You may choose to add a persistent
volume or share for that mountPoint.

Recommended configuration to disable this feature, making `/nix/store`
read-only:

```nix
microvm.writableStoreOverlay = null;
```
