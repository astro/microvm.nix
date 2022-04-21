{ runCommandNoCC, mdbook }:
runCommandNoCC "microvm.nix-doc" {
  nativeBuildInputs = [ mdbook ];
} ''
  ${mdbook}/bin/mdbook build -d $out ${../doc}
''
