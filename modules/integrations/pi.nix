{ config, ... }:
let
  inherit (config) root version;
  pi = root + "/integrations/pi";
in
{
  perSystem = { pkgs, self', ... }: {
    packages.piExtension = pkgs.runCommand "nitpick-pi-extension-${version}" { } ''
      mkdir -p $out
      cp ${pi + "/index.ts"} $out/index.ts
      cp ${pi + "/bridge.ts"} $out/bridge.ts
    '';

    # The packaged files, with the tests put next to them.
    checks.pi = pkgs.runCommand "nitpick-pi-tests" { nativeBuildInputs = [ pkgs.nodejs_24 ]; } ''
      cp ${self'.packages.piExtension}/* .
      cp ${pi + "/bridge.test.ts"} bridge.test.ts
      cp ${pi + "/index.test.ts"} index.test.ts
      node --test bridge.test.ts index.test.ts
      touch $out
    '';
  };
}
