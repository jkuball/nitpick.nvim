{ config, ... }:
let
  inherit (config) root;
  inherit (config.flake.presswerk.default) version;
  pi = root + "/integrations/pi";
in
{
  perSystem = { pkgs, self', ... }: {
    packages.integration-pi = pkgs.runCommand "nitpick-integration-pi-${version}" { } ''
      mkdir -p $out
      cp ${pi + "/index.ts"} $out/index.ts
      cp ${pi + "/bridge.ts"} $out/bridge.ts
      cp ${pi + "/nit.ts"} $out/nit.ts
    '';

    # The packaged files, with the tests put next to them.
    checks.integration-pi = pkgs.runCommand "nitpick-integration-pi-tests" { nativeBuildInputs = [ pkgs.nodejs_24 ]; } ''
      cp ${self'.packages.integration-pi}/* .
      cp ${pi + "/bridge.test.ts"} bridge.test.ts
      cp ${pi + "/index.test.ts"} index.test.ts
      cp ${pi + "/nit.test.ts"} nit.test.ts
      node --test bridge.test.ts index.test.ts nit.test.ts
      touch $out
    '';
  };
}
