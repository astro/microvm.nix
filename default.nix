(import
  (
    let lock = builtins.fromJSON (builtins.readFile ./flake.lock); in
    fetchTarball {
      url = lock.nodes.flake-compat.locked.url;
      sha256 = lock.nodes.flake-compat.locked.narHash;
    }
  )
  { src = ./.; }
).defaultNix
